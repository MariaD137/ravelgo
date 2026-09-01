-- P0 #6: one payout per driver per period. Enforced by the database so no
-- re-run, concurrent run, or double admin click can pay a driver twice.
CREATE UNIQUE INDEX "Payout_driverId_period_key" ON "Payout"("driverId", "period");
