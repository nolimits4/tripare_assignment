-- explain_benchmark.sql
-- Runs the Part 5 query twice: once with the index disabled, once with it
-- enabled, so the improvement is measured rather than asserted.
--
--   docker compose exec -T postgres \
--     psql -U hotelapp -d hotelapp -f /sql/queries/explain_benchmark.sql
--
-- (or run it through ./scripts/benchmark.sh, which mounts this for you)

\timing on

\echo ''
\echo '=============================================================='
\echo ' BASELINE: index disabled, planner is forced to scan the table'
\echo '=============================================================='

BEGIN;

-- Rather than dropping the index, hide it from the planner for this
-- transaction only. Same effect on the plan, no schema change.
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING ON)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;

ROLLBACK;

\echo ''
\echo '=============================================================='
\echo ' OPTIMISED: idx_hotel_bookings_city_created_at available'
\echo '=============================================================='

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING ON)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;

\echo ''
\echo '=============================================================='
\echo ' Result set'
\echo '=============================================================='

SELECT org_id, status, COUNT(*) AS bookings, SUM(amount) AS total_amount
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status
ORDER BY org_id, status;

\echo ''
\echo '=============================================================='
\echo ' Index sizes'
\echo '=============================================================='

SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_scan AS scans
FROM pg_stat_user_indexes
WHERE relname IN ('hotel_bookings', 'booking_events')
ORDER BY relname, indexrelname;

\timing off
