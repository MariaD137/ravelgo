import { prisma } from "../db/prisma";

/** The fixed id of the single AppSetting row — this app has exactly one. */
export const SETTINGS_ID = "default";

// Naira. Overridable per-deployment via PATCH /api/admin/settings/payment
// (Super Admin only) — see settings.routes.ts. Every change is audited.
export const DEFAULT_CASH_PAYMENT_LIMIT = 15000;
export const CASH_CURRENCY = "NGN";

export interface PaymentRuleSettings {
  cashPaymentLimit: number;
  cashPaymentEnabled: boolean;
  cardPaymentEnabled: boolean;
  walletPaymentEnabled: boolean;
}

/**
 * The single row of app-wide payment settings, created with defaults on first
 * read so there is no separate seed step. This is the one place that reads
 * or writes AppSetting — every caller (rider UI, driver charge, admin
 * settings screen) goes through here or settings.routes.ts.
 */
export async function getPaymentSettings(): Promise<PaymentRuleSettings> {
  const row = await prisma.appSetting.upsert({
    where: { id: SETTINGS_ID },
    update: {},
    create: { id: SETTINGS_ID, cashPaymentLimit: DEFAULT_CASH_PAYMENT_LIMIT },
  });
  return {
    cashPaymentLimit: row.cashPaymentLimit,
    cashPaymentEnabled: row.cashPaymentEnabled,
    cardPaymentEnabled: row.cardPaymentEnabled,
    walletPaymentEnabled: row.walletPaymentEnabled,
  };
}

/**
 * THE cash business rule. Cash is only ever a valid payment choice for a fare
 * at or below the configured limit (default ₦15,000) — and only while cash is
 * enabled at all. This must be called from every code path that can settle a
 * CASH payment (never just checked in the UI): a malicious or buggy client
 * asserting "method: CASH" on a ₦20,000 fare must still be rejected here.
 */
export async function isCashPaymentAllowed(fare: number): Promise<boolean> {
  if (!Number.isFinite(fare) || fare <= 0) return false;
  const settings = await getPaymentSettings();
  return settings.cashPaymentEnabled && fare <= settings.cashPaymentLimit;
}
