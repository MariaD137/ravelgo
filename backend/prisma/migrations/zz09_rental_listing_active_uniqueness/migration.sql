-- Prevents a vehicle from ever having more than one *active* (pending review
-- or approved) rental listing at a time, as defense-in-depth alongside the
-- application-layer check added to POST /rentals (routes/rentals.routes.ts).
-- That check closes the gap for the vast majority of requests (double-tapping
-- Submit, a network retry, the app reopening and resubmitting), but two
-- concurrent requests can both pass it before either commits — this
-- constraint makes that race impossible to slip past instead of merely
-- unlikely, the same pattern rental_bookings_exclusion_constraint already
-- uses for double-booking. A REJECTED (or, once bookings/history exist,
-- otherwise inactive) listing never counts, so a driver can always resubmit
-- the same vehicle after a rejection.
CREATE UNIQUE INDEX "RentalListing_vehicleId_active_key"
  ON "RentalListing" ("vehicleId")
  WHERE "status" IN ('PENDING_APPROVAL', 'APPROVED');
