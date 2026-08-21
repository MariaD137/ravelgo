import { prisma } from "../db/prisma";

// SECURITY: This function ONLY uses server-side pricing configuration.
// distanceKm and durationMinutes MUST come from trusted server sources
// (driver app measurement of the actual trip, NOT client-supplied estimatedFare).
// The caller is responsible for validating distance/duration bounds before calling.
export async function calculateFare(distanceKm: number, durationMinutes: number, zone?: string): Promise<number> {
  const rule = await prisma.pricingRule.findFirst({ where: { active: true }, orderBy: { createdAt: "desc" } });
  if (!rule) throw new Error("No active pricing rule configured");

  let multiplier = 1;
  if (zone) {
    const now = new Date();
    const surgeZone = await prisma.surgeZone.findFirst({
      where: {
        name: { equals: zone, mode: "insensitive" },
        active: true,
        OR: [{ startsAt: null }, { startsAt: { lte: now } }],
        AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
      },
    });
    if (surgeZone) multiplier = surgeZone.multiplier;
  }

  const baseEstimate = rule.baseFare + rule.perKm * distanceKm + rule.perMinute * durationMinutes;
  const finalFare = Math.round(baseEstimate * multiplier * 100) / 100;
  return finalFare;
}
