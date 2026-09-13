-- Tracks cumulative refunds against a Payment so a second partial refund, or
-- two concurrent refund requests racing each other, can never push total
-- refunds past the original amount — see routes/payments.routes.ts's atomic
-- claimRefund(). Existing rows have never been refunded under this tracked
-- scheme, so they default to 0 regardless of their current status.
ALTER TABLE "Payment" ADD COLUMN "refundedAmount" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Defense in depth at the DB level, same pattern as the money-amount CHECK
-- constraints elsewhere in this schema: refunds can never exceed what was
-- paid, no matter what application code does.
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_refundedAmount_check"
  CHECK ("refundedAmount" >= 0 AND "refundedAmount" <= "amount" + 0.005);
