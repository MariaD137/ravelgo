import { prisma } from "../db/prisma";

/** The fixed id of the single PricingPolicy row — this app has exactly one. */
export const PRICING_POLICY_ID = "default";

export interface PricingPolicySettings {
  rideCancellationGraceSec: number;
  rideCancellationFee: number;
  rideWaitingFreeSec: number;
  rideWaitingPerMinute: number;
  rideWaitingMaxFee: number;
  deliveryCancellationGraceSec: number;
  deliveryCancellationFee: number;
  additionalStopFee: number;
  surgeMinMultiplier: number;
  surgeMaxMultiplier: number;
  packageSizeSurcharge: Record<string, number>;
}

/**
 * The single row of cancellation/waiting/surge policy, created with the
 * reference defaults from the pricing spec on first read — same
 * singleton-on-read pattern as AppSetting/lib/payment-rules.ts, so there's no
 * separate seed step. Every write goes through PATCH /admin/pricing-policy
 * (Admin, audited).
 */
export async function getPricingPolicy(): Promise<PricingPolicySettings> {
  const row = await prisma.pricingPolicy.upsert({
    where: { id: PRICING_POLICY_ID },
    update: {},
    create: { id: PRICING_POLICY_ID },
  });
  return {
    rideCancellationGraceSec: row.rideCancellationGraceSec,
    rideCancellationFee: row.rideCancellationFee,
    rideWaitingFreeSec: row.rideWaitingFreeSec,
    rideWaitingPerMinute: row.rideWaitingPerMinute,
    rideWaitingMaxFee: row.rideWaitingMaxFee,
    deliveryCancellationGraceSec: row.deliveryCancellationGraceSec,
    deliveryCancellationFee: row.deliveryCancellationFee,
    additionalStopFee: row.additionalStopFee,
    surgeMinMultiplier: row.surgeMinMultiplier,
    surgeMaxMultiplier: row.surgeMaxMultiplier,
    packageSizeSurcharge: (row.packageSizeSurcharge as Record<string, number>) ?? {},
  };
}

/**
 * Waiting charge for a ride: free for the configured grace period after the
 * driver reports arrival, then per-minute up to a hard cap. Never negative,
 * never unbounded — a driver/admin cannot inflate this past rideWaitingMaxFee
 * no matter how long `arrivedAt` is in the past.
 */
export function computeRideWaitingCharge(
  policy: Pick<PricingPolicySettings, "rideWaitingFreeSec" | "rideWaitingPerMinute" | "rideWaitingMaxFee">,
  arrivedAt: Date,
  now: Date = new Date(),
): number {
  const waitedSec = Math.max(0, (now.getTime() - arrivedAt.getTime()) / 1000);
  const chargeableSec = Math.max(0, waitedSec - policy.rideWaitingFreeSec);
  const chargeableMinutes = Math.ceil(chargeableSec / 60);
  const charge = chargeableMinutes * policy.rideWaitingPerMinute;
  return Math.min(Math.round(charge * 100) / 100, policy.rideWaitingMaxFee);
}
