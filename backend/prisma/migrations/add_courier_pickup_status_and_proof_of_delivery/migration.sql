-- AlterEnum
ALTER TYPE "CourierStatus" ADD VALUE 'PICKED_UP';

-- AlterTable
ALTER TABLE "CourierRequest" ADD COLUMN "pickedUpAt" TIMESTAMP(3);
ALTER TABLE "CourierRequest" ADD COLUMN "deliveryPhotoKey" TEXT;
ALTER TABLE "CourierRequest" ADD COLUMN "recipientSignatureKey" TEXT;
