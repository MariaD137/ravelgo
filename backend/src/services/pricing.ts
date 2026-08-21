/**
 * Shared fare-calculation helpers, extracted from GET /pricing/quote so
 * POST /trips and PATCH /trips/:id/status can be server-authoritative using
 * the exact same PricingRule/SurgeZone data and formula the quote endpoint
 * already exposes, instead of re-implementing pricing logic in more than
 * one place.
 */

import { prisma } from "../db/prisma";

export async function getActivePricingRule() {
  return prisma.pricingRule.findFirst({ where: { active: true }, orderBy: { createdAt: "desc" } });
}

export async function getSurgeMultiplier(
  zoneName?: string,
): Promise<{ multiplier: number; surgeZoneName: string | null }> {
  if (!zoneName) return { multiplier: 1, surgeZoneName: null };

  const now = new Date();
  const surgeZone = await prisma.surgeZone.findFirst({
    where: {
      name: { equals: zoneName, mode: "insensitive" },
      active: true,
      OR: [{ startsAt: null }, { startsAt: { lte: now } }],
      AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
    },
  });
  return { multiplier: surgeZone?.multiplier ?? 1, surgeZoneName: surgeZone?.name ?? null };
}

export function computeFare(
  rule: { baseFare: number; perKm: number; perMinute: number },
  distanceKm: number,
  durationMinutes: number,
  multiplier: number,
): number {
  const baseEstimate = rule.baseFare + rule.perKm * distanceKm + rule.perMinute * durationMinutes;
  return Math.round(baseEstimate * multiplier * 100) / 100;
}

// The band a driver-submitted finalFare must fall within relative to the
// trip's own server-established estimatedFare when completing a trip.
// There's no persisted actual-distance-traveled for a trip to recompute an
// exact figure from (driver location is in-memory/live only — see
// docs/realtime-architecture.md), so bounding against the estimate is the
// smallest server-side check that still rules out an arbitrary/unrelated
// number reaching /trips/:id/charge, while leaving room for legitimate
// variance (traffic, waiting time, route changes).
export const FINAL_FARE_MIN_RATIO = 0.5;
export const FINAL_FARE_MAX_RATIO = 2.0;
