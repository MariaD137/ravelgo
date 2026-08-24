import { prisma } from "../db/prisma";

// Sanity bounds on a single trip's driver-reported metrics — not a
// business/pricing rule, just a ceiling on what's physically plausible for
// one ride, mirrored in trips.routes.ts's updateStatusSchema.
export const MAX_TRIP_DISTANCE_KM = 500;
export const MAX_TRIP_DURATION_MINUTES = 720;

export class NoPricingRuleError extends Error {
  constructor() {
    super("No active pricing rule configured");
    this.name = "NoPricingRuleError";
  }
}

/**
 * The server-authoritative fare for a completed trip: the same
 * baseFare + perKm*distance + perMinute*duration formula pricing.routes.ts
 * already uses for the pre-trip quote (GET /pricing/quote), applied here to
 * the driver-reported actual distance/duration instead of a client-supplied
 * estimate. This is the only place a Trip's finalFare is computed — the
 * driver submits trip metrics, never a dollar amount (see trips.routes.ts).
 *
 * Deliberately does not apply surge pricing: a Trip has no stored link to
 * the SurgeZone (if any) that was active when it was requested — quotes
 * only apply surge when the caller explicitly names a zone, and nothing
 * today records which zone, if any, applied to a given trip. Extending
 * surge to completion would mean inventing that association rather than
 * reusing an existing one, so it's left out here; flagged as a follow-up.
 */
export async function calculateFinalFare(distanceKm: number, durationMinutes: number): Promise<number> {
  const rule = await prisma.pricingRule.findFirst({ where: { active: true }, orderBy: { createdAt: "desc" } });
  if (!rule) throw new NoPricingRuleError();

  const amount = rule.baseFare + rule.perKm * distanceKm + rule.perMinute * durationMinutes;
  return Math.round(amount * 100) / 100;
}
