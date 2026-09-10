#!/usr/bin/env bash
#
# restore.sh - restore a dump into a fresh database and verify the result.
#
# By default the dump is restored into a brand new database next to the
# original (hotelapp_restored), so the source data is never touched and the
# two can be compared side by side.
#
# Usage:
#   ./scripts/restore.sh                          # restore the newest backup
#   ./scripts/restore.sh backups/xyz.dump         # restore a specific file
#   ./scripts/restore.sh --target mydb xyz.dump   # choose the target database
#   ./scripts/restore.sh --in-place xyz.dump      # overwrite the source database
#
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET_DB="${RESTORE_DB:-${POSTGRES_DB}_restored}"
IN_PLACE=0
DUMP_ARG=""

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t | --target)
      TARGET_DB="${2:-}"
      [ -n "$TARGET_DB" ] || die "--target needs a database name"
      shift 2
      ;;
    --in-place)
      IN_PLACE=1
      shift
      ;;
    -h | --help) usage 0 ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *)
      DUMP_ARG="$1"
      shift
      ;;
  esac
done

if [ "$IN_PLACE" -eq 1 ]; then
  TARGET_DB="$POSTGRES_DB"
fi

ensure_running
ensure_container_workdir

# --- Locate the dump ---------------------------------------------------------

if [ -n "$DUMP_ARG" ]; then
  [ -f "$DUMP_ARG" ] || die "No such file: ${DUMP_ARG}"
  DUMP_PATH="$(cd "$(dirname "$DUMP_ARG")" && pwd)/$(basename "$DUMP_ARG")"
else
  log "No dump given, selecting the most recent one in ${BACKUP_DIR}..."
  # Sort by mtime, newest first. GNU find's -printf gives "<epoch>\t<path>",
  # which sorts numerically and cuts cleanly even if a path contains spaces.
  # BSD find (macOS) has no -printf, so fall back to ls there.
  DUMP_PATH="$(
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.dump' -o -name '*.sql' \) \
      -not -name 'latest.*' -printf '%T@\t%p\n' 2>/dev/null \
      | sort -rn \
      | head -n 1 \
      | cut -f2-
  )"

  if [ -z "$DUMP_PATH" ]; then
    # shellcheck disable=SC2012  # -printf is unavailable; ls -t is the portable option
    DUMP_PATH="$(
      ls -1t "${BACKUP_DIR}"/*.dump "${BACKUP_DIR}"/*.sql 2>/dev/null \
        | grep -v '/latest\.' \
        | head -n 1 || true
    )"
  fi
  [ -n "$DUMP_PATH" ] || die "No backups found in ${BACKUP_DIR}. Run ./scripts/backup.sh first."
fi

DUMP_NAME="$(basename "$DUMP_PATH")"
CONTAINER_PATH="${CONTAINER_WORK_DIR}/${DUMP_NAME}"

# --- Verify the checksum if one was recorded ---------------------------------

CHECKSUM_FILE="${DUMP_PATH}.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
  log "Verifying checksum..."
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$DUMP_PATH")" && sha256sum --check --status "$(basename "$CHECKSUM_FILE")") \
      && ok "Checksum matches." \
      || die "Checksum mismatch. ${DUMP_NAME} is corrupt."
  else
    warn "sha256sum is unavailable; skipping checksum verification."
  fi
else
  warn "No checksum file alongside ${DUMP_NAME}; skipping verification."
fi

# --- Make the dump visible to the container ----------------------------------

log "Copying the dump into the container..."
copy_to_container "$DUMP_PATH" "$CONTAINER_PATH"

# --- Detect the format -------------------------------------------------------

if pg_exec pg_restore --list "$CONTAINER_PATH" >/dev/null 2>&1; then
  DUMP_FORMAT="custom"
else
  DUMP_FORMAT="plain"
fi

log "Dump     : ${DUMP_PATH}"
log "Format   : ${DUMP_FORMAT}"
log "Target   : ${TARGET_DB}$([ "$IN_PLACE" -eq 1 ] && echo ' (in place)')"

# --- Recreate the target database --------------------------------------------

if [ "$IN_PLACE" -eq 1 ]; then
  warn "Restoring in place over '${POSTGRES_DB}'. Existing objects will be dropped."
else
  log "Dropping and recreating '${TARGET_DB}' so the restore starts from empty..."

  # Terminate stragglers, otherwise DROP DATABASE fails on an open connection.
  psql_db postgres --quiet --command \
    "SELECT pg_terminate_backend(pid)
       FROM pg_stat_activity
      WHERE datname = '${TARGET_DB}' AND pid <> pg_backend_pid();" >/dev/null

  psql_db postgres --quiet --command "DROP DATABASE IF EXISTS \"${TARGET_DB}\";"
  psql_db postgres --quiet --command "CREATE DATABASE \"${TARGET_DB}\" OWNER \"${POSTGRES_USER}\";"
  ok "Created empty database '${TARGET_DB}'."
fi

# --- Restore -----------------------------------------------------------------

log "Restoring..."
RESTORE_LOG="${BACKUP_DIR}/restore_$(date -u +%Y%m%dT%H%M%SZ).log"

if [ "$DUMP_FORMAT" = "custom" ]; then
  # --exit-on-error would abort on the DROP statements the dump emits for
  # objects that do not exist in a fresh database, so errors are collected and
  # judged after the fact instead.
  set +e
  pg_exec pg_restore \
    --username "$POSTGRES_USER" \
    --dbname "$TARGET_DB" \
    --no-owner \
    --no-privileges \
    --verbose \
    "$CONTAINER_PATH" > "$RESTORE_LOG" 2>&1
  RESTORE_RC=$?
  set -e
else
  set +e
  pg_exec psql \
    --username "$POSTGRES_USER" \
    --dbname "$TARGET_DB" \
    --file "$CONTAINER_PATH" > "$RESTORE_LOG" 2>&1
  RESTORE_RC=$?
  set -e
fi

if [ "$RESTORE_RC" -ne 0 ]; then
  warn "The restore command exited with status ${RESTORE_RC}."
  warn "This is expected when the dump drops objects that a fresh database"
  warn "does not have yet. The verification below is what decides the outcome."
  echo "  log: ${RESTORE_LOG}"
fi

pg_exec rm -f "$CONTAINER_PATH" || warn "Could not remove the staged dump inside the container."

# --- Verify ------------------------------------------------------------------

echo ""
log "Verifying the restored database..."

TABLE_COUNT="$(psql_scalar "$TARGET_DB" \
  "SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name IN ('hotel_bookings','booking_events');")"

[ "$TABLE_COUNT" = "2" ] \
  || die "Expected both tables in '${TARGET_DB}' but found ${TABLE_COUNT}. See ${RESTORE_LOG}."
ok "Both tables are present."

BOOKINGS="$(psql_scalar "$TARGET_DB" "SELECT COUNT(*) FROM hotel_bookings;")"
EVENTS="$(psql_scalar "$TARGET_DB" "SELECT COUNT(*) FROM booking_events;")"

[ "$BOOKINGS" -gt 0 ] 2>/dev/null \
  || die "hotel_bookings is empty in the restored database. See ${RESTORE_LOG}."
ok "hotel_bookings: ${BOOKINGS} rows"
ok "booking_events: ${EVENTS} rows"

# Indexes must survive the round trip, otherwise the optimisation work in
# Part 5 would be silently lost on every recovery.
IDX="$(psql_scalar "$TARGET_DB" \
  "SELECT COUNT(*) FROM pg_indexes
    WHERE tablename = 'hotel_bookings'
      AND indexname = 'idx_hotel_bookings_city_created_at';")"
[ "$IDX" = "1" ] \
  && ok "The reporting index survived the restore." \
  || die "idx_hotel_bookings_city_created_at is missing after the restore."

# Foreign key integrity: no event may point at a booking that is not there.
ORPHANS="$(psql_scalar "$TARGET_DB" \
  "SELECT COUNT(*) FROM booking_events e
     LEFT JOIN hotel_bookings b ON b.id = e.booking_id
    WHERE b.id IS NULL;")"
[ "$ORPHANS" = "0" ] \
  && ok "No orphaned booking_events rows." \
  || die "${ORPHANS} booking_events rows have no matching booking."

# --- Compare against the source ----------------------------------------------

echo ""
log "Comparing '${TARGET_DB}' against the source database '${POSTGRES_DB}'..."

SOURCE_REPORT="$(mktemp)"
TARGET_REPORT="$(mktemp)"
trap 'rm -f "$SOURCE_REPORT" "$TARGET_REPORT"' EXIT

psql_db "$POSTGRES_DB" --quiet --file /sql/queries/verify_data.sql > "$SOURCE_REPORT" 2>/dev/null || true
psql_db "$TARGET_DB"   --quiet --file /sql/queries/verify_data.sql > "$TARGET_REPORT" 2>/dev/null || true

echo ""
echo "--- source: ${POSTGRES_DB} ---"
cat "$SOURCE_REPORT"
echo ""
echo "--- restored: ${TARGET_DB} ---"
cat "$TARGET_REPORT"
echo ""

if [ "$IN_PLACE" -eq 0 ]; then
  if diff -q "$SOURCE_REPORT" "$TARGET_REPORT" >/dev/null 2>&1; then
    ok "The two fingerprints are identical. The restore is byte-for-byte faithful."
  else
    warn "The fingerprints differ. Row-level diff:"
    diff "$SOURCE_REPORT" "$TARGET_REPORT" || true
    warn "A difference is expected only if the source changed after the backup was taken."
  fi
fi

echo ""
ok "Restore complete."
echo "  restored into : ${TARGET_DB}"
echo "  restore log   : ${RESTORE_LOG}"
echo ""
echo "Inspect it yourself with:"
echo "  docker compose exec postgres psql -U ${POSTGRES_USER} -d ${TARGET_DB} -c 'SELECT COUNT(*) FROM hotel_bookings;'"
