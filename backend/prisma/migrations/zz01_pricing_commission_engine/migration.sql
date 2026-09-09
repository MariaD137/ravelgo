-- CreateEnum
CREATE TYPE "RideVehicleClass" AS ENUM ('ECONOMY', 'COMFORT', 'PREMIUM', 'LUXURY');

-- CreateEnum
CREATE TYPE "DeliveryVehicleClass" AS ENUM ('BIKE', 'CAR', 'SUV', 'VAN');

-- CreateEnum
CREATE TYPE "FinancialTransactionType" AS ENUM ('RIDE_FARE', 'DELIVERY_FARE', 'CANCELLATION_FEE', 'WAITING_CHARGE', 'REFUND');

-- CreateEnum
CREATE TYPE "FinancialTransactionStatus" AS ENUM ('SETTLED', 'REVERSED');

-- AlterTable
ALTER TABLE "CourierRequest" ADD COLUMN     "cancellationFee" DOUBLE PRECISION,
ADD COLUMN     "commissionRate" DOUBLE PRECISION,
ADD COLUMN     "deliveryVehicleClass" "DeliveryVehicleClass",
ADD COLUMN     "driverEarnings" DOUBLE PRECISION,
ADD COLUMN     "platformCommission" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "Payment" ADD COLUMN     "courierRequestId" TEXT,
ALTER COLUMN "tripId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "arrivedAt" TIMESTAMP(3),
ADD COLUMN     "cancellationFee" DOUBLE PRECISION,
ADD COLUMN     "commissionRate" DOUBLE PRECISION,
ADD COLUMN     "driverEarnings" DOUBLE PRECISION,
ADD COLUMN     "platformCommission" DOUBLE PRECISION,
ADD COLUMN     "rideCategoryKey" TEXT,
ADD COLUMN     "waitingCharge" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "Vehicle" ADD COLUMN     "vehicleClass" "RideVehicleClass";

-- CreateTable
CREATE TABLE "RideCategory" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "benefit" TEXT,
    "baseFare" DOUBLE PRECISION NOT NULL,
    "perKm" DOUBLE PRECISION NOT NULL,
    "perMinute" DOUBLE PRECISION NOT NULL,
    "minimumFare" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "commissionRate" DOUBLE PRECISION,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "eligibleVehicleClasses" "RideVehicleClass"[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RideCategory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeliveryVehicleRate" (
    "id" TEXT NOT NULL,
    "vehicleClass" "DeliveryVehicleClass" NOT NULL,
    "name" TEXT NOT NULL,
    "initialFee" DOUBLE PRECISION NOT NULL,
    "perKm" DOUBLE PRECISION NOT NULL,
    "commissionRate" DOUBLE PRECISION,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeliveryVehicleRate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CommissionConfig" (
    "id" TEXT NOT NULL,
    "service" TEXT NOT NULL,
    "rate" DOUBLE PRECISION NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "updatedBy" TEXT,

    CONSTRAINT "CommissionConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PricingPolicy" (
    "id" TEXT NOT NULL,
    "rideCancellationGraceSec" INTEGER NOT NULL DEFAULT 120,
    "rideCancellationFee" DOUBLE PRECISION NOT NULL DEFAULT 1500,
    "rideWaitingFreeSec" INTEGER NOT NULL DEFAULT 120,
    "rideWaitingPerMinute" DOUBLE PRECISION NOT NULL DEFAULT 50,
    "rideWaitingMaxFee" DOUBLE PRECISION NOT NULL DEFAULT 250,
    "deliveryCancellationGraceSec" INTEGER NOT NULL DEFAULT 120,
    "deliveryCancellationFee" DOUBLE PRECISION NOT NULL DEFAULT 1000,
    "additionalStopFee" DOUBLE PRECISION NOT NULL DEFAULT 500,
    "surgeMinMultiplier" DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    "surgeMaxMultiplier" DOUBLE PRECISION NOT NULL DEFAULT 1.3,
    "packageSizeSurcharge" JSONB NOT NULL DEFAULT '{}',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PricingPolicy_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FinancialTransaction" (
    "id" TEXT NOT NULL,
    "type" "FinancialTransactionType" NOT NULL,
    "tripId" TEXT,
    "courierRequestId" TEXT,
    "paymentId" TEXT,
    "customerId" TEXT NOT NULL,
    "driverId" TEXT,
    "grossAmount" DOUBLE PRECISION NOT NULL,
    "commissionRate" DOUBLE PRECISION NOT NULL,
    "commissionAmount" DOUBLE PRECISION NOT NULL,
    "driverEarnings" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "paymentMethod" "PaymentMethod",
    "status" "FinancialTransactionStatus" NOT NULL DEFAULT 'SETTLED',
    "reversalOfId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "FinancialTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RideCategory_key_key" ON "RideCategory"("key");

-- CreateIndex
CREATE INDEX "RideCategory_active_sortOrder_idx" ON "RideCategory"("active", "sortOrder");

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryVehicleRate_vehicleClass_key" ON "DeliveryVehicleRate"("vehicleClass");

-- CreateIndex
CREATE UNIQUE INDEX "CommissionConfig_service_key" ON "CommissionConfig"("service");

-- CreateIndex
CREATE INDEX "FinancialTransaction_driverId_idx" ON "FinancialTransaction"("driverId");

-- CreateIndex
CREATE INDEX "FinancialTransaction_customerId_idx" ON "FinancialTransaction"("customerId");

-- CreateIndex
CREATE INDEX "FinancialTransaction_tripId_idx" ON "FinancialTransaction"("tripId");

-- CreateIndex
CREATE INDEX "FinancialTransaction_courierRequestId_idx" ON "FinancialTransaction"("courierRequestId");

-- CreateIndex
CREATE INDEX "FinancialTransaction_type_status_idx" ON "FinancialTransaction"("type", "status");

-- CreateIndex
CREATE INDEX "FinancialTransaction_createdAt_idx" ON "FinancialTransaction"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_courierRequestId_key" ON "Payment"("courierRequestId");

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_courierRequestId_fkey" FOREIGN KEY ("courierRequestId") REFERENCES "CourierRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

