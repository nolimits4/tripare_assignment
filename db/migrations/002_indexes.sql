-- 002_indexes.sql
-- Indexes supporting the reporting query in Part 5:
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi'
--     AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- Rationale is in README.md under "Query optimisation".

BEGIN;

-- Equality column first, range column second. Postgres can only use one range
-- column as a search bound and everything after it becomes a filter, so
-- (city, created_at) is usable end to end while (created_at, city) would force
-- a scan of the whole 30 day window before filtering on city.
--
-- The INCLUDE columns are the only other columns the query touches, which lets
-- the planner satisfy it with an index-only scan and never visit the heap.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);

-- Foreign keys are not indexed automatically. Without this, joining events to
-- a booking is a sequential scan, and cascading deletes on hotel_bookings scan
-- the whole events table per row.
CREATE INDEX IF NOT EXISTS idx_booking_events_booking_id_created_at
    ON booking_events (booking_id, created_at DESC);

-- Supports lookups of a single event stream by type, e.g. all payment
-- failures in the last hour.
CREATE INDEX IF NOT EXISTS idx_booking_events_event_type_created_at
    ON booking_events (event_type, created_at DESC);

-- Tenant-scoped listing, the second most common access pattern after the
-- report above.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_org_created_at
    ON hotel_bookings (org_id, created_at DESC);

COMMIT;
