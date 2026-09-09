import type { PricingRule, RideCategory, SurgeZone } from "@prisma/client";
import { prisma } from "../db/prisma";
import { Errors } from "../lib/errors";
import { roundMoney, TAX_RATE } from "../lib/money";
import { type Coordinate, haversineKm } from "../lib/geo";
import { getAllDriverLocations, locationFreshness } from "../realtime/hub";
import { resolveCommissionRate } from "./commission";

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

// ---------------------------------------------------------------------------
// Ride categories (Swift/Ease/Luxe/Elite) — each is its own full rate card,
// not a multiplier on the single PricingRule above. The single-rule
// quoteFare()/computeFare() path above is kept exactly as-is (still backs
// POST /trips and GET /pricing/quote unchanged) so nothing that already
// depends on it breaks; this is the new, additional multi-tier path.
// ---------------------------------------------------------------------------

const DEFAULT_RIDE_CATEGORIES: {
  key: string;
  name: string;
  description: string;
  benefit: string;
  baseFare: number;
  perKm: number;
  perMinute: number;
  minimumFare: number;
  sortOrder: number;
}[] = [
  { key: "SWIFT", name: "Swift", description: "Fast & affordable", benefit: "Fastest pickup", baseFare: 500, perKm: 120, perMinute: 20, minimumFare: 800, sortOrder: 0 },
  { key: "EASE", name: "Ease", description: "Comfortable everyday rides", benefit: "Extra comfort", baseFare: 800, perKm: 160, perMinute: 25, minimumFare: 1200, sortOrder: 1 },
  { key: "LUXE", name: "Luxe", description: "More space & upgraded comfort", benefit: "Spacious ride", baseFare: 1200, perKm: 220, perMinute: 35, minimumFare: 1800, sortOrder: 2 },
  { key: "ELITE", name: "Elite", description: "Premium rides & service", benefit: "Top-rated drivers", baseFare: 1800, perKm: 300, perMinute: 45, minimumFare: 2500, sortOrder: 3 },
];

/** Seed the four reference categories on first use — a no-op once Admin has rows. */
export async function ensureDefaultRideCategories(): Promise<void> {
  const count = await prisma.rideCategory.count();
  if (count > 0) return;
  await prisma.rideCategory.createMany({ data: DEFAULT_RIDE_CATEGORIES, skipDuplicates: true });
}

const AVERAGE_CITY_SPEED_KMH = 25;

export interface CategoryQuote {
  categoryKey: string;
  name: string;
  description: string;
  benefit: string | null;
  estimatedFare: number;
  subtotal: number;
  tax: number;
  taxRate: number;
  surgeMultiplier: number;
  distanceKm: number;
  tripEtaMinutes: number;
  pickupEtaMinutes: number | null;
  availability: "AVAILABLE" | "LIMITED" | "UNAVAILABLE";
  commissionRate: number;
}

function categoryBaseFare(category: Pick<RideCategory, "name" | "baseFare" | "perKm" | "perMinute">) {
  return { name: category.name, baseFare: category.baseFare, perKm: category.perKm, perMinute: category.perMinute };
}

/**
 * The authoritative fare for ONE category — used by POST /trips at request
 * time (never GET /pricing/categories's availability-scanning variant, which
 * is display-only and must never gate what a trip is actually charged).
 * Throws Errors.conflict via the caller's lookup when the key doesn't match
 * an active category.
 */
export async function quoteFareForCategory(
  category: RideCategory,
  distanceKm: number,
  durationMinutes: number,
  zone?: string,
): Promise<FareBreakdown & { minimumFare: number }> {
  const surge = await findActiveSurgeZone(zone);
  const base = computeFare(categoryBaseFare(category), distanceKm, durationMinutes, surge);
  return { ...base, estimatedFare: roundMoney(Math.max(base.estimatedFare, category.minimumFare)), minimumFare: category.minimumFare };
}

/**
 * A quote for every active ride category for one route — what the "Choose
 * your ride" screen renders. Availability and pickup ETA are computed from
 * real online, eligible, currently-free drivers and their real last-known
 * location (never fabricated): a category with zero eligible online drivers
 * shows UNAVAILABLE with no pickup estimate at all, one with a single
 * candidate shows LIMITED, otherwise AVAILABLE.
 */
export async function quoteAllCategories(
  pickup: Coordinate,
  distanceKm: number,
  durationMinutes: number,
  zone?: string,
): Promise<CategoryQuote[]> {
  await ensureDefaultRideCategories();
  const [categories, surge, candidates] = await Promise.all([
    prisma.rideCategory.findMany({ where: { active: true }, orderBy: { sortOrder: "asc" } }),
    findActiveSurgeZone(zone),
    prisma.driver.findMany({
      where: {
        status: "ACTIVE",
        isOnline: true,
        tripsAsDriver: { none: { status: { in: ["MATCHED", "IN_PROGRESS"] } } },
      },
      include: { vehicles: { where: { isPrimary: true }, take: 1 } },
    }),
  ]);
  const locationByDriver = new Map(getAllDriverLocations().map((l) => [l.driverId, l]));

  return Promise.all(
    categories.map(async (category) => {
      const base = computeFare(categoryBaseFare(category), distanceKm, durationMinutes, surge);
      const estimatedFare = roundMoney(Math.max(base.estimatedFare, category.minimumFare));
      const commissionRate = await resolveCommissionRate("RIDE", category.commissionRate);

      const eligible = category.eligibleVehicleClasses.length === 0
        ? candidates
        : candidates.filter((d) => {
            const vehicleClass = d.vehicles[0]?.vehicleClass;
            return vehicleClass != null && category.eligibleVehicleClasses.includes(vehicleClass);
          });

      let pickupEtaMinutes: number | null = null;
      let nearestKm = Infinity;
      for (const d of eligible) {
        const loc = locationByDriver.get(d.id);
        if (!loc || locationFreshness(loc.updatedAt) !== "LIVE") continue;
        const km = haversineKm(pickup, { lat: loc.lat, lng: loc.lng });
        if (km < nearestKm) nearestKm = km;
      }
      if (nearestKm !== Infinity) {
        pickupEtaMinutes = Math.max(1, Math.round((nearestKm / AVERAGE_CITY_SPEED_KMH) * 60));
      }

      const availability: CategoryQuote["availability"] =
        eligible.length === 0 ? "UNAVAILABLE" : eligible.length === 1 ? "LIMITED" : "AVAILABLE";

      return {
        categoryKey: category.key,
        name: category.name,
        description: category.description,
        benefit: category.benefit,
        estimatedFare,
        subtotal: base.subtotal,
        tax: base.tax,
        taxRate: base.taxRate,
        surgeMultiplier: base.surgeMultiplier,
        distanceKm,
        tripEtaMinutes: Math.round(durationMinutes),
        pickupEtaMinutes,
        availability,
        commissionRate,
      };
    }),
  );
}
