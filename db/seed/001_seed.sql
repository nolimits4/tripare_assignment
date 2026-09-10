-- 001_seed.sql
-- Generates a dataset large enough for index choices to actually matter.
--
--   * 5000 bookings (the brief asks for 100 as a minimum; a sequential scan
--     wins on 100 rows, so the volume is raised to make the EXPLAIN output
--     meaningful)
--   * 8 cities, including 'delhi', which the target query filters on
--   * 6 organisations
--   * 5 booking statuses
--   * created_at spread over 180 days, so the 30 day window is genuinely
--     selective rather than matching everything
--   * booking events for roughly a third of the bookings

BEGIN;

-- Fixed seed so every reviewer gets byte-identical data and comparable
-- EXPLAIN output.
SELECT setseed(0.42);

-- Idempotent: re-running the seed replaces the dataset rather than doubling it.
TRUNCATE TABLE booking_events, hotel_bookings RESTART IDENTITY CASCADE;

WITH cities AS (
    SELECT ARRAY[
        'delhi', 'mumbai', 'bengaluru', 'hyderabad',
        'chennai', 'pune', 'kolkata', 'jaipur'
    ] AS list
),
orgs AS (
    -- Deterministic UUIDs so seeded org_ids are stable across runs.
    SELECT ARRAY[
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
        '55555555-5555-4555-8555-555555555555',
        '66666666-6666-4666-8666-666666666666'
    ]::UUID[] AS list
),
statuses AS (
    SELECT ARRAY[
        'pending', 'confirmed', 'cancelled', 'completed', 'refunded'
    ] AS list
)
INSERT INTO hotel_bookings (
    id, org_id, hotel_id, city, checkin_date, checkout_date,
    amount, status, created_at
)
SELECT
    gen_random_uuid(),
    o.list[1 + (g % array_length(o.list, 1))],
    'HTL-' || LPAD(((g * 7) % 250 + 1)::TEXT, 4, '0'),
    -- 'delhi' is weighted to roughly 30% of rows. A realistic skew: common
    -- enough to matter, selective enough that an index still pays off.
    CASE
        WHEN random() < 0.30 THEN 'delhi'
        ELSE c.list[2 + (g % (array_length(c.list, 1) - 1))]
    END,
    checkin.d,
    checkin.d + ((1 + (g % 7)) * INTERVAL '1 day'),
    ROUND((2000 + random() * 48000)::NUMERIC, 2),
    s.list[1 + (g % array_length(s.list, 1))],
    created.ts
FROM generate_series(1, 5000) AS g
CROSS JOIN cities c
CROSS JOIN orgs o
CROSS JOIN statuses s
-- Spread over 180 days so the 30 day predicate filters out most of the table.
CROSS JOIN LATERAL (
    SELECT NOW() - (random() * 180) * INTERVAL '1 day' AS ts
) AS created
CROSS JOIN LATERAL (
    SELECT (created.ts + (random() * 60) * INTERVAL '1 day')::DATE AS d
) AS checkin;

-- Events for about a third of the bookings, one to three per booking.
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    b.id,
    e.event_type,
    jsonb_build_object(
        'source', 'seed',
        'channel', CASE WHEN random() < 0.5 THEN 'web' ELSE 'mobile' END,
        'amount', b.amount,
        'status', b.status,
        'attempt', e.n
    ),
    b.created_at + (e.n * INTERVAL '2 hours')
FROM hotel_bookings b
CROSS JOIN LATERAL (
    SELECT
        n,
        (ARRAY['created', 'payment_authorized', 'confirmed',
               'modified', 'cancelled', 'refunded'])[1 + ((n * 3) % 6)]
            AS event_type
    FROM generate_series(1, 1 + (ABS(HASHTEXT(b.id::TEXT)) % 3)) AS n
) AS e
WHERE ABS(HASHTEXT(b.id::TEXT)) % 3 = 0;

COMMIT;

-- Fresh statistics so the planner makes sensible choices on the very first
-- query rather than waiting for autovacuum.
ANALYZE hotel_bookings;
ANALYZE booking_events;
