/**
 * RavelGo's commission engine — the single place a gross fare is split into
 * "RavelGo's cut" and "driver earnings". Replaces the old hardcoded
 * PLATFORM_COMMISSION_RATE constant (lib/money.ts) with a DB-driven,
 * Admin-configurable rate per service ("RIDE", "DELIVERY"), with an optional
 * per-category/per-vehicle-class override.
 *
 * Nothing here recomputes a rate for an already-settled transaction — that
 * would violate the "immutable after settlement" requirement. Callers read
 * the *current* rate only at the moment a transaction is first settled
 * (services/ledger.ts), then persist the resulting numbers permanently on
 * the Trip/CourierRequest/FinancialTransaction rows.
 */

import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { roundMoney } from "../lib/money";

/** True for Prisma's "unique constraint violated" error (P2002). */
function isUniqueConstraintViolation(err: unknown): boolean {
  return err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002";
}

export type CommissionServiceKey = "RIDE" | "DELIVERY";

// The business default (spec: "RavelGo Commission = 20%, Driver = 80%",
// overriding the client document's stray "Ride commission: 15%" — see
// PR/task description). Only used to seed CommissionConfig on first read;
// once a row exists, Admin's stored rate always wins.
export const DEFAULT_COMMISSION_RATE = 0.2;

/**
 * The Admin-configured default commission rate for a whole service, upserted
 * with the platform default on first read so there's no separate seed step —
 * the same singleton-on-read pattern lib/payment-rules.ts uses for AppSetting.
 */
export async function getServiceCommissionRate(service: CommissionServiceKey): Promise<number> {
  try {
    const row = await prisma.commissionConfig.upsert({
      where: { service },
      update: {},
      create: { service, rate: DEFAULT_COMMISSION_RATE },
    });
    return row.rate;
  } catch (err) {
    // Two callers seeding the same service concurrently (e.g. a multi-category
    // fare quote resolving RIDE's rate for each category in parallel) can both
    // race past the upsert's own read and both attempt the create — the loser
    // hits a real P2002 on the now-unique `service` column. The row DOES
    // exist at that point (the winner just created it), so read it back
    // rather than surfacing a spurious 500 for what is, from the caller's
    // perspective, a successful read.
    if (isUniqueConstraintViolation(err)) {
      const row = await prisma.commissionConfig.findUniqueOrThrow({ where: { service } });
      return row.rate;
    }
    throw err;
  }
}

/** Every configured service commission rate, for the admin dashboard. */
export async function listCommissionConfig(): Promise<{ service: string; rate: number; updatedAt: Date; updatedBy: string | null }[]> {
  await Promise.all([getServiceCommissionRate("RIDE"), getServiceCommissionRate("DELIVERY")]);
  return prisma.commissionConfig.findMany({ orderBy: { service: "asc" } });
}

/**
 * The effective rate for one specific category/vehicle-class: its own
 * override when set, else the service-wide default. This is what's actually
 * applied to a real transaction — never the bare service default alone,
 * since a category may have deliberately opted out of it.
 */
export async function resolveCommissionRate(
  service: CommissionServiceKey,
  categoryOverride: number | null | undefined,
): Promise<number> {
  if (categoryOverride != null) return categoryOverride;
  return getServiceCommissionRate(service);
}

export interface CommissionSplit {
  commissionRate: number;
  commissionAmount: number;
  driverEarnings: number;
}

/**
 * Split a gross amount into RavelGo's commission and the driver's earnings.
 * Uses integer-cent arithmetic (spec #36: no floating-point drift) so
 * commissionAmount + driverEarnings always reconciles exactly back to the
 * rounded gross amount — never a cent short or over.
 */
export function splitCommission(grossAmount: number, rate: number): CommissionSplit {
  if (!Number.isFinite(grossAmount) || grossAmount < 0) {
    throw new Error("grossAmount must be a finite, non-negative number");
  }
  if (!Number.isFinite(rate) || rate < 0 || rate > 1) {
    throw new Error("commission rate must be between 0 and 1");
  }
  const grossCents = Math.round(grossAmount * 100);
  const commissionCents = Math.round(grossCents * rate);
  const driverCents = grossCents - commissionCents;
  return {
    commissionRate: rate,
    commissionAmount: roundMoney(commissionCents / 100),
    driverEarnings: roundMoney(driverCents / 100),
  };
}

/**
 * Admin: set a service's default commission rate. Validated here (not just
 * at the zod layer) so no caller can ever persist a negative or >100% rate —
 * defense in depth against a future call site that forgets to validate.
 */
export async function setServiceCommissionRate(
  service: CommissionServiceKey,
  rate: number,
  updatedBy: string,
): Promise<{ service: string; rate: number; updatedAt: Date; updatedBy: string | null }> {
  if (!Number.isFinite(rate) || rate < 0 || rate > 1) {
    throw new Error("Commission rate must be between 0 and 1 (0%–100%)");
  }
  return prisma.commissionConfig.upsert({
    where: { service },
    update: { rate, updatedBy },
    create: { service, rate, updatedBy },
  });
}
