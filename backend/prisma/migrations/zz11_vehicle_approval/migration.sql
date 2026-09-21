-- CreateEnum
CREATE TYPE "VehicleApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- AlterTable
ALTER TABLE "Vehicle" ADD COLUMN     "approvalStatus" "VehicleApprovalStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "rejectionReason" TEXT;

-- Backfill: a vehicle whose owning driver is already ACTIVE has been in real
-- operation this whole time with no vehicle-level gate at all — introducing
-- one now must not suddenly strand an already-active driver's vehicle mid-use.
-- Only a vehicle owned by a driver still PENDING_REVIEW or SUSPENDED starts
-- PENDING (that driver isn't providing service yet regardless of this field).
-- A vehicle created after this migration still defaults to PENDING via the
-- column default above, so review is enforced going forward for new vehicles.
UPDATE "Vehicle" v
SET "approvalStatus" = 'APPROVED'
FROM "Driver" d
WHERE v."driverId" = d.id AND d.status = 'ACTIVE';
