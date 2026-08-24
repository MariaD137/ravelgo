-- Row-level security for the three financial tables (bank account numbers
-- and payment/payout amounts). This is a defense-in-depth backstop behind
-- the app-layer requireAuth/requireRole + ownership checks, not a
-- replacement for them — see backend/src/lib/rls.ts for how the app sets
-- the session variables these policies read.
--
-- FORCE ROW LEVEL SECURITY (not just ENABLE) so this also applies to the
-- table owner / migration role, not only to non-owner roles as Postgres
-- does by default — otherwise RLS would silently do nothing, since this
-- app currently uses a single Postgres role for both migrations and
-- runtime queries.

ALTER TABLE "DriverBankAccount" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "DriverBankAccount" FORCE ROW LEVEL SECURITY;

CREATE POLICY driver_bank_account_owner_or_bypass ON "DriverBankAccount"
  USING ("driverId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true')
  WITH CHECK ("driverId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true');

ALTER TABLE "Payment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Payment" FORCE ROW LEVEL SECURITY;

CREATE POLICY payment_owner_or_bypass ON "Payment"
  USING ("userId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true')
  WITH CHECK ("userId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true');

ALTER TABLE "Payout" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Payout" FORCE ROW LEVEL SECURITY;

CREATE POLICY payout_owner_or_bypass ON "Payout"
  USING ("driverId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true')
  WITH CHECK ("driverId" = current_setting('app.user_id', true) OR current_setting('app.bypass', true) = 'true');
