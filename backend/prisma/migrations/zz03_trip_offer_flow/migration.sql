-- AlterEnum
ALTER TYPE "TripStatus" ADD VALUE 'OFFERED';

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "declinedDriverIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "offerExpiresAt" TIMESTAMP(3);
