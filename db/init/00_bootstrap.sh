#!/bin/bash
# Runs once, on first container start, via the postgres entrypoint.
#
# Migrations and seed data are mounted read-only at /sql. Applying them from
# here, rather than dropping them straight into /docker-entrypoint-initdb.d,
# guarantees every migration runs before any seed file regardless of how the
# entrypoint sorts directory entries.
set -euo pipefail

SQL_DIR="${SQL_DIR:-/sql}"

apply_dir() {
  local dir="$1"
  local label="$2"
  local file
  local found=0

  if [ ! -d "$dir" ]; then
    echo "bootstrap: no ${label} directory at ${dir}, skipping"
    return 0
  fi

  for file in "$dir"/*.sql; do
    [ -e "$file" ] || continue
    found=1
    echo "bootstrap: applying ${label} $(basename "$file")"
    psql --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --set ON_ERROR_STOP=1 \
      --quiet \
      --file "$file"
  done

  if [ "$found" -eq 0 ]; then
    echo "bootstrap: no ${label} files found in ${dir}"
  fi
}

apply_dir "${SQL_DIR}/migrations" "migration"
apply_dir "${SQL_DIR}/seed" "seed"

echo "bootstrap: schema and seed data are ready"
