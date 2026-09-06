-- CreateTable
CREATE TABLE "AppSetting" (
    "id" TEXT NOT NULL,
    "cashPaymentLimit" DOUBLE PRECISION NOT NULL DEFAULT 15000,
    "cashPaymentEnabled" BOOLEAN NOT NULL DEFAULT true,
    "cardPaymentEnabled" BOOLEAN NOT NULL DEFAULT true,
    "walletPaymentEnabled" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AppSetting_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CashRemittance" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "note" TEXT,
    "recordedBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CashRemittance_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CashRemittance_driverId_idx" ON "CashRemittance"("driverId");

-- AddForeignKey
ALTER TABLE "CashRemittance" ADD CONSTRAINT "CashRemittance_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
