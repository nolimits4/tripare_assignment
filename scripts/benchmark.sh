#!/usr/bin/env bash
#
# benchmark.sh - run the Part 5 query with and without the reporting index
# and print both EXPLAIN (ANALYZE, BUFFERS) plans.
#
# Usage:
#   ./scripts/benchmark.sh
#
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ensure_running

log "Refreshing planner statistics..."
psql_db "$POSTGRES_DB" --quiet --command "ANALYZE hotel_bookings; ANALYZE booking_events;"

psql_db "$POSTGRES_DB" --file /sql/queries/explain_benchmark.sql
