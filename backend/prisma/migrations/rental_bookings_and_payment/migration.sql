-- CreateEnum
CREATE TYPE "RentalBookingStatus" AS ENUM ('PENDING_PAYMENT', 'CONFIRMED', 'CANCELLED', 'COMPLETED');

-- AlterEnum
ALTER TYPE "WalletTransactionType" ADD VALUE 'RENTAL_PAYMENT';

-- AlterTable
ALTER TABLE "WalletTransaction" ADD COLUMN     "rentalBookingId" TEXT;

-- CreateTable
CREATE TABLE "RentalBooking" (
    "id" TEXT NOT NULL,
    "renterId" TEXT NOT NULL,
    "listingId" TEXT NOT NULL,
    "startDate" TIMESTAMP(3) NOT NULL,
    "endDate" TIMESTAMP(3) NOT NULL,
    "days" INTEGER NOT NULL,
    "totalPrice" DOUBLE PRECISION NOT NULL,
    "status" "RentalBookingStatus" NOT NULL DEFAULT 'PENDING_PAYMENT',
    "paymentMethod" "PaymentMethod",
    "paymentStatus" "PaymentStatus" NOT NULL DEFAULT 'PENDING',
    "providerReference" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RentalBooking_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RentalBooking_providerReference_key" ON "RentalBooking"("providerReference");

-- CreateIndex
CREATE INDEX "RentalBooking_renterId_idx" ON "RentalBooking"("renterId");

-- CreateIndex
CREATE INDEX "RentalBooking_listingId_idx" ON "RentalBooking"("listingId");

-- AddForeignKey
ALTER TABLE "RentalBooking" ADD CONSTRAINT "RentalBooking_renterId_fkey" FOREIGN KEY ("renterId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RentalBooking" ADD CONSTRAINT "RentalBooking_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "RentalListing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
