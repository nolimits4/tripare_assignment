-- 001_schema.sql
-- Core booking tables.

BEGIN;

-- gen_random_uuid() lives in pgcrypto on PostgreSQL 12 and earlier; on 13+ it
-- is built in. Creating the extension keeps the script portable either way.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID           NOT NULL,
    hotel_id      VARCHAR(100)   NOT NULL,
    city          VARCHAR(100)   NOT NULL,
    checkin_date  DATE           NOT NULL,
    checkout_date DATE           NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50)    NOT NULL,
    created_at    TIMESTAMP      NOT NULL DEFAULT NOW(),

    CONSTRAINT hotel_bookings_dates_ck CHECK (checkout_date > checkin_date),
    CONSTRAINT hotel_bookings_amount_ck CHECK (amount >= 0),
    CONSTRAINT hotel_bookings_status_ck CHECK (
        status IN ('pending', 'confirmed', 'cancelled', 'completed', 'refunded')
    )
);

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL PRIMARY KEY,
    booking_id UUID         NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT booking_events_booking_fk
        FOREIGN KEY (booking_id)
        REFERENCES hotel_bookings (id)
        ON DELETE CASCADE
);

COMMENT ON TABLE hotel_bookings IS 'One row per hotel booking.';
COMMENT ON TABLE booking_events IS 'Append-only audit trail of state changes per booking.';

COMMIT;
