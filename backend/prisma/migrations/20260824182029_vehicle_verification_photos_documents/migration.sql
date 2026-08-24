-- CreateEnum
CREATE TYPE "VehicleVerificationStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'RESUBMISSION_REQUIRED');

-- CreateEnum
CREATE TYPE "VehicleType" AS ENUM ('SEDAN', 'SUV', 'VAN', 'TRUCK', 'MOTORCYCLE', 'LUXURY', 'OTHER');

-- CreateEnum
CREATE TYPE "VehiclePhotoType" AS ENUM ('FRONT', 'REAR', 'LEFT_SIDE', 'RIGHT_SIDE', 'INTERIOR', 'OTHER');

-- CreateEnum
CREATE TYPE "DriverDocumentType" AS ENUM ('DRIVERS_LICENSE', 'VEHICLE_REGISTRATION', 'INSURANCE', 'INSPECTION', 'ROADWORTHINESS', 'BACKGROUND_CHECK', 'PROOF_OF_ADDRESS', 'OTHER');

-- AlterTable
ALTER TABLE "DriverDocument" ADD COLUMN     "documentType" "DriverDocumentType" NOT NULL DEFAULT 'OTHER',
ADD COLUMN     "rejectionReason" TEXT,
ADD COLUMN     "reviewedAt" TIMESTAMP(3),
ADD COLUMN     "reviewedById" TEXT,
ADD COLUMN     "vehicleId" TEXT;

-- AlterTable
-- `updatedAt` is added nullable, backfilled, then locked to NOT NULL below —
-- Prisma's own migration diff would otherwise add it as NOT NULL with no
-- default, which fails outright against any pre-existing Vehicle row (see
-- PRE_AWS_DRIVER_ADMIN_MONITORING_READINESS.md / docs/PRD.md migration
-- safety notes: existing driver/vehicle records must survive a migration).
ALTER TABLE "Vehicle" ADD COLUMN     "isActive" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "updatedAt" TIMESTAMP(3),
ADD COLUMN     "vehicleType" "VehicleType" NOT NULL DEFAULT 'OTHER',
ADD COLUMN     "verificationReason" TEXT,
ADD COLUMN     "verificationStatus" "VehicleVerificationStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "verifiedAt" TIMESTAMP(3),
ADD COLUMN     "verifiedById" TEXT,
ADD COLUMN     "vin" TEXT;

-- Backfill any pre-existing rows before enforcing NOT NULL below.
UPDATE "Vehicle" SET "updatedAt" = "createdAt" WHERE "updatedAt" IS NULL;

ALTER TABLE "Vehicle" ALTER COLUMN "updatedAt" SET NOT NULL;

-- CreateTable
CREATE TABLE "VehiclePhoto" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "fileKey" TEXT NOT NULL,
    "photoType" "VehiclePhotoType" NOT NULL DEFAULT 'OTHER',
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VehiclePhoto_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "VehiclePhoto_vehicleId_displayOrder_idx" ON "VehiclePhoto"("vehicleId", "displayOrder");

-- AddForeignKey
ALTER TABLE "Vehicle" ADD CONSTRAINT "Vehicle_verifiedById_fkey" FOREIGN KEY ("verifiedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehiclePhoto" ADD CONSTRAINT "VehiclePhoto_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverDocument" ADD CONSTRAINT "DriverDocument_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverDocument" ADD CONSTRAINT "DriverDocument_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
