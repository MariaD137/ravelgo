-- CreateEnum PayoutStatus
CREATE TYPE "PayoutStatus" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED');

-- CreateTable DriverBankAccount
CREATE TABLE "DriverBankAccount" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "accountHolderName" TEXT NOT NULL,
    "bankName" TEXT NOT NULL,
    "accountNumber" TEXT NOT NULL,
    "routingNumber" TEXT NOT NULL,
    "accountType" TEXT NOT NULL DEFAULT 'CHECKING',
    "isVerified" BOOLEAN NOT NULL DEFAULT false,
    "verificationToken" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DriverBankAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable Payout
CREATE TABLE "Payout" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "status" "PayoutStatus" NOT NULL DEFAULT 'PENDING',
    "period" TEXT NOT NULL,
    "transactionId" TEXT,
    "failureReason" TEXT,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Payout_pkey" PRIMARY KEY ("id")
);

-- CreateIndex DriverBankAccount_driverId_key
CREATE UNIQUE INDEX "DriverBankAccount_driverId_key" ON "DriverBankAccount"("driverId");

-- CreateIndex Payout_driverId_idx
CREATE INDEX "Payout_driverId_idx" ON "Payout"("driverId");

-- CreateIndex Payout_status_idx
CREATE INDEX "Payout_status_idx" ON "Payout"("status");

-- CreateIndex Payout_createdAt_idx
CREATE INDEX "Payout_createdAt_idx" ON "Payout"("createdAt");

-- AddForeignKey DriverBankAccount
ALTER TABLE "DriverBankAccount" ADD CONSTRAINT "DriverBankAccount_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey Payout
ALTER TABLE "Payout" ADD CONSTRAINT "Payout_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
