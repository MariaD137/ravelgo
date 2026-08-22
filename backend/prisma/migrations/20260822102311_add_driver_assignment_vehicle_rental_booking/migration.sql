-- CreateEnum
CREATE TYPE "AssignmentType" AS ENUM ('RIDE', 'COURIER', 'RENTAL');

-- CreateEnum
CREATE TYPE "AssignmentStatus" AS ENUM ('ACTIVE', 'ENDED');

-- CreateEnum
CREATE TYPE "RentalBookingStatus" AS ENUM ('REQUESTED', 'CONFIRMED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'REJECTED');

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "vehicleId" TEXT;

-- CreateTable
CREATE TABLE "DriverAssignment" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "assignmentType" "AssignmentType" NOT NULL,
    "assignmentId" TEXT NOT NULL,
    "vehicleId" TEXT,
    "status" "AssignmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),

    CONSTRAINT "DriverAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RentalBooking" (
    "id" TEXT NOT NULL,
    "rentalListingId" TEXT NOT NULL,
    "renterId" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3) NOT NULL,
    "status" "RentalBookingStatus" NOT NULL DEFAULT 'REQUESTED',
    "price" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RentalBooking_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DriverAssignment_driverId_idx" ON "DriverAssignment"("driverId");

-- CreateIndex
CREATE INDEX "DriverAssignment_assignmentType_assignmentId_idx" ON "DriverAssignment"("assignmentType", "assignmentId");

-- CreateIndex
CREATE INDEX "DriverAssignment_vehicleId_idx" ON "DriverAssignment"("vehicleId");

-- CreateIndex
CREATE INDEX "RentalBooking_vehicleId_status_idx" ON "RentalBooking"("vehicleId", "status");

-- AddForeignKey
ALTER TABLE "Trip" ADD CONSTRAINT "Trip_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverAssignment" ADD CONSTRAINT "DriverAssignment_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverAssignment" ADD CONSTRAINT "DriverAssignment_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RentalBooking" ADD CONSTRAINT "RentalBooking_rentalListingId_fkey" FOREIGN KEY ("rentalListingId") REFERENCES "RentalListing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RentalBooking" ADD CONSTRAINT "RentalBooking_renterId_fkey" FOREIGN KEY ("renterId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RentalBooking" ADD CONSTRAINT "RentalBooking_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Hand-written: enforces "at most one ACTIVE assignment per driver" at the
-- database level, not just in application code. Prisma's schema DSL has no
-- WHERE clause for @@unique, so a plain `@@unique([driverId])` would wrongly
-- forbid a driver from ever having more than one *historical* (ENDED)
-- assignment. A partial unique index is the correct primitive here: it only
-- constrains rows matching the predicate, so ended assignments never
-- collide, while two concurrent inserts racing to create an ACTIVE row for
-- the same driver will have the second one rejected by Postgres itself
-- (unique_violation, Prisma error code P2002) regardless of which
-- transaction, process, or App Runner instance issued it. This is the
-- backstop behind services/driver-availability.ts's application-level
-- check, not a replacement for it — the app-level check gives a clean
-- DRIVER_BUSY response in the common case; this index is what makes that
-- guarantee true even under a genuine race or a bypassed application layer.
CREATE UNIQUE INDEX "DriverAssignment_driverId_active_unique"
  ON "DriverAssignment"("driverId")
  WHERE "status" = 'ACTIVE';
