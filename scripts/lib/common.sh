#!/usr/bin/env bash
# Shared configuration and helpers for the database scripts.
# Sourced, not executed.

set -euo pipefail

# Repository root, regardless of where the caller invoked the script from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load .env if present so the scripts and docker compose agree on credentials.
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env"
  set +a
fi

# Defaults match docker-compose.yml.
PG_SERVICE="${PG_SERVICE:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-hotelapp}"
POSTGRES_USER="${POSTGRES_USER:-hotelapp}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-hotelapp_local_pw}"

BACKUP_DIR="${BACKUP_DIR:-${REPO_ROOT}/backups}"
# Path the same directory is mounted at inside the container.
CONTAINER_BACKUP_DIR="/backups"

# --- Output ------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_INFO=$'\033[0;36m'
  C_OK=$'\033[0;32m'
  C_WARN=$'\033[0;33m'
  C_ERR=$'\033[0;31m'
else
  C_RESET='' C_INFO='' C_OK='' C_WARN='' C_ERR=''
fi

log()  { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }

# --- Docker compose ----------------------------------------------------------

# Resolves to "docker compose" or the older "docker-compose".
compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${REPO_ROOT}/docker-compose.yml" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "${REPO_ROOT}/docker-compose.yml" "$@"
  else
    die "Neither 'docker compose' nor 'docker-compose' is available on PATH."
  fi
}

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH."
  docker info >/dev/null 2>&1 || die "The Docker daemon is not reachable. Is Docker Desktop running?"
}

# Runs a command inside the postgres container with PGPASSWORD already set.
# -T disables TTY allocation, which keeps output pipeable.
pg_exec() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_SERVICE" "$@"
}

# psql against the given database (defaults to POSTGRES_DB), quiet and strict.
psql_db() {
  local db="${1:-$POSTGRES_DB}"
  shift || true
  pg_exec psql \
    --username "$POSTGRES_USER" \
    --dbname "$db" \
    --set ON_ERROR_STOP=1 \
    "$@"
}

# Same, but returns a bare value with no headers or padding.
psql_scalar() {
  local db="$1"
  local sql="$2"
  psql_db "$db" --tuples-only --no-align --command "$sql" | tr -d '[:space:]'
}

wait_for_postgres() {
  local attempts="${1:-30}"
  local i

  log "Waiting for PostgreSQL to accept connections..."
  for ((i = 1; i <= attempts; i++)); do
    if pg_exec pg_isready --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" >/dev/null 2>&1; then
      ok "PostgreSQL is ready."
      return 0
    fi
    sleep 2
  done

  die "PostgreSQL was not ready after $((attempts * 2))s. Check: docker compose logs ${PG_SERVICE}"
}

ensure_running() {
  require_docker

  if ! compose ps --status running --services 2>/dev/null | grep -qx "$PG_SERVICE"; then
    log "The ${PG_SERVICE} service is not running. Starting it..."
    compose up -d "$PG_SERVICE"
  fi

  wait_for_postgres
}
