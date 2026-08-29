import type { PricingRule, SurgeZone } from "@prisma/client";
import { prisma } from "../db/prisma";
import { Errors } from "../lib/errors";
import { roundMoney, TAX_RATE } from "../lib/money";

export interface FareBreakdown {
  // Fare before tax (base + distance + time, times surge).
  subtotal: number;
  taxRate: number;
  tax: number;
  // Tax-inclusive total the rider actually pays and is charged/held for. This
  // is what gets stored on the trip and what commission is computed on.
  estimatedFare: number;
  pricingRule: string;
  surgeMultiplier: number;
  surgeZone: string | null;
}

/**
 * The one place a fare is computed from a rate card. Both GET /pricing/quote
 * and POST /trips call this, so a rider's quoted estimate and the estimate
 * actually stored on their trip can never diverge — and neither is ever a
 * number the client simply asserted. The returned `estimatedFare` is the
 * tax-inclusive total (subtotal + VAT).
 */
export function computeFare(
  rule: Pick<PricingRule, "name" | "baseFare" | "perKm" | "perMinute">,
  distanceKm: number,
  durationMinutes: number,
  surge?: Pick<SurgeZone, "name" | "multiplier"> | null,
): FareBreakdown {
  const multiplier = surge?.multiplier ?? 1;
  const base = rule.baseFare + rule.perKm * distanceKm + rule.perMinute * durationMinutes;
  const subtotal = roundMoney(base * multiplier);
  const tax = roundMoney(subtotal * TAX_RATE);
  const estimatedFare = roundMoney(subtotal + tax);
  return {
    subtotal,
    taxRate: TAX_RATE,
    tax,
    estimatedFare,
    pricingRule: rule.name,
    surgeMultiplier: multiplier,
    surgeZone: surge?.name ?? null,
  };
}

/** The currently-active rate card, or a 409 if the operator hasn't set one. */
export async function requireActivePricingRule(): Promise<PricingRule> {
  const rule = await prisma.pricingRule.findFirst({ where: { active: true }, orderBy: { createdAt: "desc" } });
  if (!rule) throw Errors.conflict("No active pricing rule configured");
  return rule;
}

/** An active surge zone matching `zone` by name (case-insensitive, in-window), or null. */
export async function findActiveSurgeZone(zone: string | undefined): Promise<SurgeZone | null> {
  if (!zone) return null;
  const now = new Date();
  return prisma.surgeZone.findFirst({
    where: {
      name: { equals: zone, mode: "insensitive" },
      active: true,
      OR: [{ startsAt: null }, { startsAt: { lte: now } }],
      AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
    },
  });
}

/** Compute an authoritative fare for the given trip inputs against live pricing. */
export async function quoteFare(
  distanceKm: number,
  durationMinutes: number,
  zone?: string,
): Promise<FareBreakdown> {
  const rule = await requireActivePricingRule();
  const surge = await findActiveSurgeZone(zone);
  return computeFare(rule, distanceKm, durationMinutes, surge);
}
