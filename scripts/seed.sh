#!/usr/bin/env bash
#
# seed.sh - reapply migrations and seed data to the running database.
#
# The compose entrypoint only runs migrations on a brand new volume, so this
# is the way to reset the dataset without destroying the container.
#
# Usage:
#   ./scripts/seed.sh
#
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ensure_running

for file in "${REPO_ROOT}"/db/migrations/*.sql; do
  log "Applying migration $(basename "$file")"
  psql_db "$POSTGRES_DB" --quiet --file "/sql/migrations/$(basename "$file")"
done

for file in "${REPO_ROOT}"/db/seed/*.sql; do
  log "Applying seed $(basename "$file")"
  psql_db "$POSTGRES_DB" --quiet --file "/sql/seed/$(basename "$file")"
done

echo ""
psql_db "$POSTGRES_DB" --file /sql/queries/verify_data.sql
echo ""
ok "Schema and seed data reapplied."
