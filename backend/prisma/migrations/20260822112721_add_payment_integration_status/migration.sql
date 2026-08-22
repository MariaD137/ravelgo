-- CreateEnum
CREATE TYPE "PaymentIntegrationStatus" AS ENUM ('NOT_CONFIGURED');

-- AlterTable
ALTER TABLE "CourierRequest" ADD COLUMN     "paymentStatus" "PaymentIntegrationStatus" NOT NULL DEFAULT 'NOT_CONFIGURED';

-- AlterTable
ALTER TABLE "RentalBooking" ADD COLUMN     "paymentStatus" "PaymentIntegrationStatus" NOT NULL DEFAULT 'NOT_CONFIGURED';
