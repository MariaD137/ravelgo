-- Referral programme (rider invites rider).
--
-- Fully additive: one new table, one new enum, one nullable column on "User",
-- four defaulted columns on the single "AppSetting" row, and one new value on
-- an existing enum. No existing row is rewritten and nothing is dropped, so
-- every current User/AppSetting row stays valid exactly as it is.
--
-- "referralEnabled" defaults to FALSE on purpose: applying this migration
-- must never start paying real money out of real wallets. An admin turns the
-- programme on deliberately via PATCH /api/admin/settings/referral.
--
-- The ALTER TYPE below only ADDS a value; it is not read in this migration,
-- which is what makes it safe inside Prisma's transaction on PostgreSQL 12+.

-- CreateEnum
CREATE TYPE "ReferralStatus" AS ENUM ('PENDING', 'REWARDED');
-- AlterEnum
ALTER TYPE "WalletTransactionType" ADD VALUE 'REFERRAL_BONUS';
-- AlterTable
ALTER TABLE "AppSetting" ADD COLUMN     "referralEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "referralQualifyingTrips" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "referralRefereeRewardAmount" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN     "referralRewardAmount" DOUBLE PRECISION NOT NULL DEFAULT 1000;
-- AlterTable
ALTER TABLE "User" ADD COLUMN     "referralCode" TEXT;
-- CreateTable
CREATE TABLE "Referral" (
    "id" TEXT NOT NULL,
    "referrerId" TEXT NOT NULL,
    "refereeId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "status" "ReferralStatus" NOT NULL DEFAULT 'PENDING',
    "referrerRewardAmount" DOUBLE PRECISION,
    "refereeRewardAmount" DOUBLE PRECISION,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "rewardedAt" TIMESTAMP(3),
    CONSTRAINT "Referral_pkey" PRIMARY KEY ("id")
);
-- CreateIndex
CREATE UNIQUE INDEX "Referral_refereeId_key" ON "Referral"("refereeId");
-- CreateIndex
CREATE INDEX "Referral_referrerId_status_idx" ON "Referral"("referrerId", "status");
-- CreateIndex
CREATE INDEX "Referral_status_createdAt_idx" ON "Referral"("status", "createdAt");
-- CreateIndex
CREATE UNIQUE INDEX "User_referralCode_key" ON "User"("referralCode");
-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_referrerId_fkey" FOREIGN KEY ("referrerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
-- AddForeignKey
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_refereeId_fkey" FOREIGN KEY ("refereeId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
