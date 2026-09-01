-- P0 #10: coordinates the server computes fare distance from (client never
-- asserts distanceKm). P2: indexes on the busiest table in the product.
ALTER TABLE "Trip" ADD COLUMN "pickupLat" DOUBLE PRECISION;
ALTER TABLE "Trip" ADD COLUMN "pickupLng" DOUBLE PRECISION;
ALTER TABLE "Trip" ADD COLUMN "dropoffLat" DOUBLE PRECISION;
ALTER TABLE "Trip" ADD COLUMN "dropoffLng" DOUBLE PRECISION;
ALTER TABLE "Trip" ADD COLUMN "distanceKm" DOUBLE PRECISION;

CREATE INDEX "Trip_riderId_idx" ON "Trip"("riderId");
CREATE INDEX "Trip_driverId_idx" ON "Trip"("driverId");
CREATE INDEX "Trip_status_idx" ON "Trip"("status");
CREATE INDEX "Trip_completedAt_idx" ON "Trip"("completedAt");
