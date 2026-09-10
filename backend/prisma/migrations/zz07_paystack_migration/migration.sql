-- Stripe -> Paystack payment provider migration.
--
-- Non-destructive: no existing row's stored currency/reference value is
-- touched. Only DEFAULTs change (so new rows are correct going forward) and
-- new nullable columns are added. Every pre-existing Payment/RentalBooking/
-- WalletTransaction row predates this migration, so it was necessarily
-- created under the Stripe-only system -- it is backfilled to provider =
-- 'STRIPE' below for accurate historical labeling, then the column DEFAULT
-- is flipped to 'PAYSTACK' so the application code (which now always sets
-- provider explicitly on create) has a safe fallback.

CREATE TYPE "PaymentProvider" AS ENUM ('STRIPE', 'PAYSTACK');

-- Payment
ALTER TABLE "Payment" ADD COLUMN "provider" "PaymentProvider" NOT NULL DEFAULT 'STRIPE';
ALTER TABLE "Payment" ALTER COLUMN "provider" SET DEFAULT 'PAYSTACK';
ALTER TABLE "Payment" ALTER COLUMN "currency" SET DEFAULT 'NGN';

-- RentalBooking
ALTER TABLE "RentalBooking" ADD COLUMN "provider" "PaymentProvider" NOT NULL DEFAULT 'STRIPE';
ALTER TABLE "RentalBooking" ALTER COLUMN "provider" SET DEFAULT 'PAYSTACK';

-- WalletTransaction
ALTER TABLE "WalletTransaction" ADD COLUMN "provider" "PaymentProvider" NOT NULL DEFAULT 'STRIPE';
ALTER TABLE "WalletTransaction" ALTER COLUMN "provider" SET DEFAULT 'PAYSTACK';

-- WalletAccount
ALTER TABLE "WalletAccount" ALTER COLUMN "currency" SET DEFAULT 'NGN';

-- FinancialTransaction
ALTER TABLE "FinancialTransaction" ALTER COLUMN "currency" SET DEFAULT 'NGN';

-- Payout: nullable, no backfill needed -- NULL correctly means "not moved by
-- an automated provider transfer" for every payout that predates Paystack
-- Transfers (all of them completed, if at all, via completePayout()'s manual
-- admin-entered reference).
ALTER TABLE "Payout" ADD COLUMN "provider" "PaymentProvider";
ALTER TABLE "Payout" ALTER COLUMN "currency" SET DEFAULT 'NGN';

-- DriverBankAccount: new Paystack Transfer Recipient fields. routingNumber /
-- accountType are deliberately left in place (US-shaped, unused by Paystack)
-- -- see the schema comment -- so no existing driver bank record loses data;
-- routingNumber is relaxed to optional since a Nigerian driver's account has
-- no such value to supply going forward.
ALTER TABLE "DriverBankAccount" ADD COLUMN "bankCode" TEXT;
ALTER TABLE "DriverBankAccount" ADD COLUMN "paystackRecipientCode" TEXT;
ALTER TABLE "DriverBankAccount" ALTER COLUMN "routingNumber" DROP NOT NULL;
