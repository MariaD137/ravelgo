/**
 * Delivery pricing — replaces the old hardcoded flat SMALL/MEDIUM/LARGE
 * PACKAGE_PRICES table (courier.routes.ts) with the vehicle-class-based rate
 * card (initial fee + per-km) the pricing spec calls for, plus a small
 * additive surcharge by package size (PricingPolicy.packageSizeSurcharge) for
 * the weight/size differentiation the old table used to provide.
 */

import type { DeliveryVehicleClass, PackageSize } from "@prisma/client";
import { prisma } from "../db/prisma";
import { roundMoney } from "../lib/money";
import { getPricingPolicy } from "../lib/pricing-policy";
import { resolveCommissionRate } from "./commission";

const DEFAULT_DELIVERY_RATES: { vehicleClass: DeliveryVehicleClass; name: string; initialFee: number; perKm: number }[] = [
  { vehicleClass: "BIKE", name: "Bike", initialFee: 700, perKm: 150 },
  { vehicleClass: "CAR", name: "Car", initialFee: 1000, perKm: 200 },
  { vehicleClass: "SUV", name: "SUV", initialFee: 1300, perKm: 250 },
  { vehicleClass: "VAN", name: "Van", initialFee: 1800, perKm: 300 },
];

/** Seed the four reference vehicle-class rates on first use — same
 * pattern as ensureDefaultRideCategories. A no-op once Admin has rows. */
export async function ensureDefaultDeliveryVehicleRates(): Promise<void> {
  const count = await prisma.deliveryVehicleRate.count();
  if (count > 0) return;
  await prisma.deliveryVehicleRate.createMany({ data: DEFAULT_DELIVERY_RATES, skipDuplicates: true });
}

// Fallback for a request with no resolved pickup/dropoff coordinates (an
// older client build, or an address that never geocoded) so pricing never
// breaks even without a distance to price against — see courier.routes.ts.
export const LEGACY_PACKAGE_PRICES: Record<string, number> = { SMALL: 800, MEDIUM: 1500, LARGE: 2500 };

export interface DeliveryQuote {
  vehicleClass: DeliveryVehicleClass;
  name: string;
  estimatedFare: number;
  initialFee: number;
  distanceFee: number;
  packageSurcharge: number;
  commissionRate: number;
}

/** A single vehicle class's quote for a given distance + package size. */
export async function quoteDelivery(
  vehicleClass: DeliveryVehicleClass,
  distanceKm: number,
  packageSize: PackageSize,
): Promise<DeliveryQuote> {
  await ensureDefaultDeliveryVehicleRates();
  const rate = await prisma.deliveryVehicleRate.findUnique({ where: { vehicleClass } });
  if (!rate || !rate.active) {
    throw new Error(`No active delivery rate configured for vehicle class ${vehicleClass}`);
  }

  const policy = await getPricingPolicy();
  const packageSurcharge = policy.packageSizeSurcharge[packageSize] ?? 0;
  const distanceFee = roundMoney(rate.perKm * Math.max(0, distanceKm));
  const estimatedFare = roundMoney(rate.initialFee + distanceFee + packageSurcharge);
  const commissionRate = await resolveCommissionRate("DELIVERY", rate.commissionRate);

  return {
    vehicleClass,
    name: rate.name,
    estimatedFare,
    initialFee: rate.initialFee,
    distanceFee,
    packageSurcharge,
    commissionRate,
  };
}

/** Every active vehicle class's quote, for a "choose your delivery vehicle" screen. */
export async function quoteAllDeliveryVehicles(distanceKm: number, packageSize: PackageSize): Promise<DeliveryQuote[]> {
  await ensureDefaultDeliveryVehicleRates();
  const rates = await prisma.deliveryVehicleRate.findMany({ where: { active: true }, orderBy: { initialFee: "asc" } });
  return Promise.all(rates.map((r) => quoteDelivery(r.vehicleClass, distanceKm, packageSize)));
}
