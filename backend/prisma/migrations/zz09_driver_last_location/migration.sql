-- Additive: persist each driver's last reported position so trip matching
-- can prefer the nearest eligible driver (services/matching.ts). Nullable —
-- existing rows simply have no known location until their next ping.
ALTER TABLE "Driver" ADD COLUMN "lastLat" DOUBLE PRECISION;
ALTER TABLE "Driver" ADD COLUMN "lastLng" DOUBLE PRECISION;
ALTER TABLE "Driver" ADD COLUMN "lastLocationAt" TIMESTAMP(3);

CREATE INDEX "Driver_status_isOnline_lastLocationAt_idx" ON "Driver"("status", "isOnline", "lastLocationAt");
