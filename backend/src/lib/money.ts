import { z } from "zod";

/**
 * Central monetary guardrails. Every value that can move money — a fare, a
 * charge, a payout — is validated against these, so no single route can be
 * the one place a negative, non-finite, absurdly large, or sub-cent amount
 * slips through.
 *
 * These are deliberately generous absolute bounds (denominated in the app's
 * single currency, USD): they exist to stop obviously-malicious or
 * obviously-broken values (0, -5, 1e12, NaN), NOT to encode real pricing —
 * real pricing lives in PricingRule/SurgeZone and services/pricing.ts.
 */

// No legitimate single fare or payout in this product approaches this. It's a
// backstop against an integer-overflow-style abuse value, not a business cap.
export const MAX_MONEY_AMOUNT = 100_000;

// A driver may adjust the final fare up from the estimate for real reasons
// (waiting time, a longer actual route), but not without bound. The final
// fare is anchored to the server-computed estimate within this multiple; a
// value outside the band is rejected rather than silently charged.
export const MAX_FINAL_FARE_MULTIPLIER = 2.0;
// The final fare can also come in lower than the estimate (shortcut, promo),
// but a near-zero charge against a real estimate is a red flag worth
// rejecting so it can't be used to zero out a fare the rider owes.
export const MIN_FINAL_FARE_MULTIPLIER = 0.5;

// VAT applied on top of the base fare. Nigeria VAT is 7.5%. A single global
// rate is intentional for this stage — if per-region tax is ever needed it
// belongs on PricingRule/SurgeZone, not scattered through the routes. Kept
// deliberately separate from RavelGo's commission (services/commission.ts) —
// government VAT and RavelGo's own cut must never be presented as the same
// line item (see the pricing spec's tax-separation requirement).
export const TAX_RATE = 0.075;

// RavelGo's commission rate now lives in the DB (CommissionConfig, one row
// per service, Admin-configurable) rather than as a hardcoded constant here
// — see services/commission.ts. The old flat PLATFORM_COMMISSION_RATE (25%,
// applied uniformly to every ride regardless of tier, and even to cash trips
// the driver already held) has been removed; services/commission.ts's
// DEFAULT_COMMISSION_RATE (20%) is only ever used to seed that DB row on
// first read, never applied directly to a transaction.

/** Round a currency amount to whole cents (2 dp), avoiding float drift. */
export function roundMoney(amount: number): number {
  return Math.round(amount * 100) / 100;
}

/**
 * A zod schema for any client-supplied monetary amount: finite, strictly
 * positive, at most two decimal places (whole cents), and within the
 * absolute cap. Reused everywhere a request body carries money.
 */
export const moneyAmountSchema = z
  .number()
  .finite("Amount must be a finite number")
  .positive("Amount must be greater than zero")
  .max(MAX_MONEY_AMOUNT, `Amount must not exceed ${MAX_MONEY_AMOUNT}`)
  .refine((n) => Number.isInteger(Math.round(n * 100)) && Math.abs(n * 100 - Math.round(n * 100)) < 1e-9, {
    message: "Amount must have at most two decimal places",
  });

/** Round to whole cents — the canonical representation before any charge. */
export function toCents(amount: number): number {
  return Math.round(amount * 100);
}

/** Convert integer cents (e.g. a stored wallet balance) back to a currency amount. */
export function fromCents(cents: number): number {
  return roundMoney(cents / 100);
}
