-- AlterEnum
ALTER TYPE "WalletTransactionType" ADD VALUE 'DELIVERY_PAYMENT';

-- AlterTable
ALTER TABLE "WalletTransaction" ADD COLUMN     "courierRequestId" TEXT;

