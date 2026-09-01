-- P0 #12: preserve financial history. Soft-delete marker on User, and flip the
-- financial relations from ON DELETE CASCADE/SET NULL to RESTRICT so a user
-- with payout/wallet/trip history can never be hard-deleted (deactivate via
-- deletedAt instead). Constraint names are Prisma's defaults.
ALTER TABLE "User" ADD COLUMN "deletedAt" TIMESTAMP(3);

ALTER TABLE "Payout" DROP CONSTRAINT "Payout_driverId_fkey";
ALTER TABLE "Payout" ADD CONSTRAINT "Payout_driverId_fkey"
  FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "WalletAccount" DROP CONSTRAINT "WalletAccount_userId_fkey";
ALTER TABLE "WalletAccount" ADD CONSTRAINT "WalletAccount_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Trip" DROP CONSTRAINT "Trip_driverId_fkey";
ALTER TABLE "Trip" ADD CONSTRAINT "Trip_driverId_fkey"
  FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
