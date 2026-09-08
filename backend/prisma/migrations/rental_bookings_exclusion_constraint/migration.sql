-- AA-4: hard, database-level guarantee against double-booking a rental
-- vehicle, as defense-in-depth alongside the existing application-layer
-- check (the overlap query inside the transaction in
-- POST /rentals/:id/book, routes/rentals.routes.ts). That check closes the
-- gap for the vast majority of requests, but two concurrent transactions can
-- both pass it before either commits — this constraint makes that race
-- impossible to slip past instead of merely unlikely: a second overlapping
-- INSERT for the same listing is rejected by Postgres itself.
--
-- btree_gist is required to use a GiST exclusion index on the "listingId"
-- equality term alongside the date-range overlap term below.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE "RentalBooking"
  ADD CONSTRAINT "RentalBooking_no_overlapping_active_bookings"
  EXCLUDE USING gist (
    "listingId" WITH =,
    tsrange("startDate", "endDate") WITH &&
  )
  WHERE ("status" IN ('PENDING_PAYMENT', 'CONFIRMED'));
