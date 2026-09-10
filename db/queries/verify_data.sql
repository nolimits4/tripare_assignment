-- verify_data.sql
-- Fingerprint of the dataset. backup.sh and restore.sh both run this so the
-- two outputs can be compared line for line.

SELECT 'hotel_bookings' AS table_name, COUNT(*) AS row_count FROM hotel_bookings
UNION ALL
SELECT 'booking_events', COUNT(*) FROM booking_events
UNION ALL
SELECT 'distinct_cities', COUNT(DISTINCT city) FROM hotel_bookings
UNION ALL
SELECT 'distinct_orgs', COUNT(DISTINCT org_id) FROM hotel_bookings
UNION ALL
SELECT 'distinct_statuses', COUNT(DISTINCT status) FROM hotel_bookings
UNION ALL
-- Amounts are scaled to an integer so the checksum is not sensitive to how
-- psql happens to format numerics.
SELECT 'amount_checksum', COALESCE(SUM((amount * 100)::BIGINT), 0) FROM hotel_bookings
UNION ALL
SELECT 'indexes_on_bookings', COUNT(*) FROM pg_indexes WHERE tablename = 'hotel_bookings'
UNION ALL
SELECT 'indexes_on_events', COUNT(*) FROM pg_indexes WHERE tablename = 'booking_events'
ORDER BY table_name;
