-- CreateEnum
CREATE TYPE "TripOfferStatus" AS ENUM ('OFFERED', 'ACCEPTED', 'DECLINED', 'EXPIRED');

-- CreateTable
CREATE TABLE "TripOffer" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "status" "TripOfferStatus" NOT NULL DEFAULT 'OFFERED',
    "offeredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "respondedAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TripOffer_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TripOffer_tripId_idx" ON "TripOffer"("tripId");

-- CreateIndex
CREATE INDEX "TripOffer_driverId_status_idx" ON "TripOffer"("driverId", "status");

-- AddForeignKey
ALTER TABLE "TripOffer" ADD CONSTRAINT "TripOffer_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "Trip"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TripOffer" ADD CONSTRAINT "TripOffer_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Hand-written: enforces "at most one OFFERED (outstanding, unanswered)
-- offer per driver at a time" at the database level — the same
-- hand-written-partial-unique-index pattern as
-- DriverAssignment_driverId_active_unique and
-- Trip_riderId_open_unique/CourierRequest_senderId_open_unique (Prisma's
-- schema DSL has no WHERE clause for @@unique). This is what makes
-- offerNextDriver's own application-level "exclude drivers who already
-- have an OFFERED offer" pre-check a true guarantee rather than just a
-- fast path: two concurrent attempts to offer the same driver a ride
-- (e.g. two different trips both selecting them as the best eligible
-- driver in the same instant) can't both insert an OFFERED row — Postgres
-- rejects the loser (unique_violation, Prisma error code P2002)
-- regardless of which transaction committed first. Resolved/expired
-- offers (ACCEPTED/DECLINED/EXPIRED) are excluded from the predicate, so
-- a driver's full offer history is never constrained by this index.
CREATE UNIQUE INDEX "TripOffer_driverId_offered_unique"
  ON "TripOffer"("driverId")
  WHERE "status" = 'OFFERED';
