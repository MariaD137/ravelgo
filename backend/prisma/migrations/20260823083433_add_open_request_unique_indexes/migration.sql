-- Hand-written: enforces "at most one open Trip per rider" and "at most one
-- open CourierRequest per sender" at the database level, backstopping the
-- application-level pre-check (`openTrip`/`openRequest`, in
-- trips.routes.ts / courier.routes.ts) that already exists for a double-tap
-- or client retry. That check reads-then-writes across two separate
-- statements, so a true concurrent double-submit (two requests racing,
-- sub-millisecond apart) could still slip both inserts through before
-- either commits. Prisma's schema DSL has no WHERE clause for @@unique, so
-- (as with DriverAssignment_driverId_active_unique) this is a hand-written
-- partial unique index rather than something expressible in schema.prisma
-- directly: it only constrains rows in a non-terminal status, so completed/
-- cancelled/disputed trips (and delivered/cancelled courier requests) never
-- collide, while a genuine concurrent race is rejected by Postgres itself
-- (unique_violation, Prisma error code P2002) regardless of which
-- transaction or App Runner instance issued it.
CREATE UNIQUE INDEX "Trip_riderId_open_unique"
  ON "Trip"("riderId")
  WHERE "status" IN ('REQUESTED', 'MATCHED', 'IN_PROGRESS');

CREATE UNIQUE INDEX "CourierRequest_senderId_open_unique"
  ON "CourierRequest"("senderId")
  WHERE "status" IN ('REQUESTED', 'MATCHED', 'IN_TRANSIT');
