-- SE-4: a payment-provider/bank-wire transaction reference must never be
-- shared by two payouts. NULLs are unaffected (Postgres allows multiple NULLs
-- in a unique index), so this only constrains payouts that have actually
-- been completed with a real reference.
CREATE UNIQUE INDEX "Payout_transactionId_key" ON "Payout"("transactionId");
