#!/usr/bin/env bash
#
# backup.sh - create a timestamped dump of the local PostgreSQL database.
#
# Usage:
#   ./scripts/backup.sh                 # dump the default database
#   ./scripts/backup.sh --format plain  # plain SQL instead of custom format
#   ./scripts/backup.sh --keep 5        # prune all but the newest 5 backups
#
# Output:
#   backups/<db>_<UTC timestamp>.dump   the dump itself
#   backups/<db>_<UTC timestamp>.dump.sha256
#   backups/<db>_<UTC timestamp>.manifest.txt   row counts at dump time
#   backups/latest.dump                 symlink or copy of the newest dump
#
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

FORMAT="custom"
KEEP=0

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -f | --format)
      FORMAT="${2:-}"
      [ -n "$FORMAT" ] || die "--format needs a value: custom or plain"
      shift 2
      ;;
    -k | --keep)
      KEEP="${2:-}"
      [[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep needs a non-negative integer"
      shift 2
      ;;
    -h | --help) usage 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
done

case "$FORMAT" in
  custom) DUMP_FLAG="--format=custom"; EXT="dump" ;;
  plain)  DUMP_FLAG="--format=plain";  EXT="sql" ;;
  *) die "Unsupported format '${FORMAT}'. Use custom or plain." ;;
esac

ensure_running
ensure_container_workdir

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASENAME="${POSTGRES_DB}_${TIMESTAMP}.${EXT}"
HOST_PATH="${BACKUP_DIR}/${BASENAME}"
CONTAINER_PATH="${CONTAINER_WORK_DIR}/${BASENAME}"

log "Database : ${POSTGRES_DB}"
log "Format   : ${FORMAT}"
log "Target   : ${HOST_PATH}"

# Record what the data looked like at dump time. restore.sh regenerates the
# same report against the restored database so the two can be diffed.
MANIFEST="${BACKUP_DIR}/${POSTGRES_DB}_${TIMESTAMP}.manifest.txt"
log "Capturing pre-backup row counts..."
{
  echo "# Backup manifest"
  echo "# created_at : $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "# database   : ${POSTGRES_DB}"
  echo "# dump_file  : ${BASENAME}"
  echo ""
  psql_db "$POSTGRES_DB" --file /sql/queries/verify_data.sql
} > "$MANIFEST"

log "Running pg_dump..."
# --clean --if-exists lets the dump be replayed over a database that already
# has objects; the restore path uses a fresh database anyway, but this keeps
# the artefact useful for in-place recovery too.
pg_exec pg_dump \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  "$DUMP_FLAG" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --verbose \
  --file "$CONTAINER_PATH"

# Verify the archive is readable before calling the backup good. For custom
# format this parses the table of contents; a truncated file fails here.
if [ "$FORMAT" = "custom" ]; then
  log "Verifying archive integrity..."
  pg_exec pg_restore --list "$CONTAINER_PATH" > /dev/null \
    || die "The dump is not a readable pg_restore archive."
fi

log "Copying the dump out of the container..."
copy_from_container "$CONTAINER_PATH" "$HOST_PATH"

# The container copy has served its purpose; leaving it would grow the
# container's writable layer on every run.
pg_exec rm -f "$CONTAINER_PATH" || warn "Could not remove the temporary dump inside the container."

[ -s "$HOST_PATH" ] || die "pg_dump produced no output at ${HOST_PATH}."

# Checksum, so a corrupted transfer is detectable later.
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$BACKUP_DIR" && sha256sum "$BASENAME" > "${BASENAME}.sha256")
elif command -v shasum >/dev/null 2>&1; then
  (cd "$BACKUP_DIR" && shasum -a 256 "$BASENAME" > "${BASENAME}.sha256")
else
  warn "No sha256sum or shasum found; skipping the checksum file."
fi

# Convenience pointer for restore.sh. Symlinks are unreliable on Windows
# filesystems, so fall back to a copy.
LATEST="${BACKUP_DIR}/latest.${EXT}"
rm -f "$LATEST"
ln -s "$BASENAME" "$LATEST" 2>/dev/null || cp "$HOST_PATH" "$LATEST"

# Optional retention.
if [ "$KEEP" -gt 0 ]; then
  log "Pruning old backups, keeping the newest ${KEEP}..."
  # shellcheck disable=SC2012
  ls -1t "${BACKUP_DIR}/${POSTGRES_DB}"_*."${EXT}" 2>/dev/null \
    | tail -n "+$((KEEP + 1))" \
    | while read -r old; do
        log "  removing $(basename "$old")"
        rm -f "$old" "${old}.sha256" "${old%.*}.manifest.txt"
      done
fi

SIZE="$(du -h "$HOST_PATH" | cut -f1)"

echo ""
ok "Backup complete."
echo "  file      : ${HOST_PATH}"
echo "  size      : ${SIZE}"
echo "  manifest  : ${MANIFEST}"
echo "  latest    : ${LATEST}"
echo ""
echo "Restore it with:"
echo "  ./scripts/restore.sh ${HOST_PATH}"
