import { prisma } from "../db/prisma";

// A driver may be actively committed to at most one of a ride or a delivery
// at a time — accepting a ride while already carrying a package (or vice
// versa) is a real product-integrity bug, not just a UX nicety, since the
// driver is physically in one place. Enforced here, at the DB-query level, on
// every path that could create the conflict: the ride-matching candidate
// query (services/matching.ts), the ride accept endpoint, and the courier
// accept endpoint — never left to the Flutter UI alone (P0: "the backend must
// be authoritative").
//
// "Active" deliberately includes OFFERED for rides: a driver mid-decision on
// one offer should not simultaneously be offered (or accept) a delivery, and
// vice versa — otherwise a driver could accept both within the same
// multi-second window before either side's own state settles.
const ACTIVE_TRIP_STATUSES = ["OFFERED", "MATCHED", "IN_PROGRESS"] as const;
const ACTIVE_COURIER_STATUSES = ["MATCHED", "PICKED_UP", "IN_TRANSIT"] as const;

export async function driverHasActiveRide(driverId: string): Promise<boolean> {
  const count = await prisma.trip.count({
    where: { driverId, status: { in: [...ACTIVE_TRIP_STATUSES] } },
  });
  return count > 0;
}

export async function driverHasActiveDelivery(driverId: string): Promise<boolean> {
  const count = await prisma.courierRequest.count({
    where: { driverId, status: { in: [...ACTIVE_COURIER_STATUSES] } },
  });
  return count > 0;
}

/** True if this driver may be offered/accept a NEW ride right now. */
export async function driverEligibleForNewRide(driverId: string): Promise<boolean> {
  return !(await driverHasActiveDelivery(driverId));
}

/** True if this driver may accept a NEW delivery right now. */
export async function driverEligibleForNewDelivery(driverId: string): Promise<boolean> {
  return !(await driverHasActiveRide(driverId));
}

/**
 * Every driver eligible to be OFFERED a brand-new delivery right now:
 * admin-approved (ACTIVE — excludes SUSPENDED and PENDING_REVIEW), online,
 * and not already committed to a conflicting ride or delivery. Used to fan
 * out the "new delivery available" push notification (P2 #6) — this is a
 * pure read, so a failure here must never affect delivery creation itself
 * (see courier.routes.ts, which wraps the call in try/catch for exactly
 * that reason).
 */
export async function findEligibleDriversForNewDelivery(): Promise<{ userId: string }[]> {
  return prisma.driver.findMany({
    where: {
      status: "ACTIVE",
      isOnline: true,
      tripsAsDriver: { none: { status: { in: ["OFFERED", "MATCHED", "IN_PROGRESS"] } } },
      courierRequestsHandled: { none: { status: { in: ["MATCHED", "PICKED_UP", "IN_TRANSIT"] } } },
    },
    select: { userId: true },
  });
}
