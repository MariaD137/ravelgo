-- Records the payer's Cognito sub when a wallet TOPUP was funded by an
-- authorized third party rather than the wallet owner. Null for self top-ups.
ALTER TABLE "WalletTransaction" ADD COLUMN "fundedBySub" TEXT;
