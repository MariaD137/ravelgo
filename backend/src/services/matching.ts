import type { RideVehicleClass, Trip } from "@prisma/client";
import { prisma } from "../db/prisma";
import { broadcastTripStatus } from "../realtime/hub";
import { notifyUser } from "../lib/notifications";
import { driverHasActiveDelivery } from "../lib/driver-conflicts";

// How long a single driver has to accept or decline an offered trip before it
// is released back to the pool and re-offered to the next eligible driver
// (see expireStaleOffers below). Short enough that a rider isn't stuck behind
// one unresponsive driver for long, long enough for a real human to look at
// their phone and tap a button.
export const OFFER_TTL_SECONDS = 20;

/**
 * Server-authoritative dispatch (P0 #3 special requirement): a ride is never
 * silently "matched" — it is OFFERED to exactly one eligible driver at a
 * time, who must actually call POST /trips/:id/accept for it to become
 * MATCHED. A decline (POST /trips/:id/decline) or a silent timeout
 * (expireStaleOffers) releases the offer and re-offers it to the next
 * eligible driver, excluding everyone who has already declined/timed out on
 * this specific trip (Trip.declinedDriverIds).
 *
 * Deliberately not location-aware yet: there's no driver location in
 * Postgres today (RT-02's location stream is in-memory only, see
 * src/realtime/hub.ts) and no PostGIS/geo index to query against. "First
 * available ACTIVE driver, highest rated" is the honest MVP algorithm this
 * data supports — swap in a real distance-based query once driver location
 * is itself persisted somewhere queryable.
 */
async function findNextEligibleDriver(trip: Trip) {
  let eligibleClasses: RideVehicleClass[] = [];
  if (trip.rideCategoryKey) {
    const category = await prisma.rideCategory.findUnique({ where: { key: trip.rideCategoryKey } });
    eligibleClasses = category?.eligibleVehicleClasses ?? [];
  }

  return prisma.driver.findFirst({
    where: {
      status: "ACTIVE",
      isOnline: true,
      id: { notIn: trip.declinedDriverIds },
      // A driver already OFFERED/MATCHED/IN_PROGRESS on another ride, or
      // actively carrying a delivery (MATCHED/PICKED_UP/IN_TRANSIT), must
      // never be offered a second, conflicting job at the same time (P0:
      // "a driver must not simultaneously be assigned to incompatible
      // active workflows" — see lib/driver-conflicts.ts for the same rule
      // enforced again, defensively, at accept time).
      tripsAsDriver: { none: { status: { in: ["OFFERED", "MATCHED", "IN_PROGRESS"] } } },
      courierRequestsHandled: { none: { status: { in: ["MATCHED", "PICKED_UP", "IN_TRANSIT"] } } },
      ...(eligibleClasses.length > 0
        ? { vehicles: { some: { isPrimary: true, vehicleClass: { in: eligibleClasses } } } }
        : {}),
    },
    orderBy: { rating: "desc" },
  });
}

/**
 * Offer a REQUESTED trip to the next eligible driver. Returns the updated
 * trip (status OFFERED) if someone was found, or null if nobody is currently
 * eligible (the trip stays REQUESTED, to be retried by matchPendingTrips
 * later). Also used to re-offer after a decline/expiry, since those release
 * the trip back to REQUESTED first.
 */
export async function matchDriverToTrip(tripId: string) {
  const trip = await prisma.trip.findUnique({ where: { id: tripId } });
  if (!trip || trip.status !== "REQUESTED") return null;

  const driver = await findNextEligibleDriver(trip);
  if (!driver) return null;

  const offered = await prisma.trip.update({
    where: { id: tripId },
    data: {
      driverId: driver.id,
      status: "OFFERED",
      offerExpiresAt: new Date(Date.now() + OFFER_TTL_SECONDS * 1000),
    },
    include: { rider: true, driver: { include: { user: true, vehicles: true } } },
  });

  await notifyUser(
    driver.userId,
    "RIDE_OFFERED",
    "New ride request",
    "You have a new ride request. Open the app to accept.",
    { type: "TRIP", id: offered.id },
  );

  return offered;
}

/**
 * Driver accepts an OFFERED trip. Atomic conditional update (updateMany,
 * not findUnique-then-update) so two concurrent accept calls for the same
 * offer — or an accept racing a decline/expiry — can only ever have one
 * winner; every loser gets a clean "offer no longer available" rather than
 * corrupting state. The `offerExpiresAt: { gt: now } ` clause folds the
 * expiry check into the same atomic operation, so an accept can never sneak
 * through after the offer has technically timed out even if the background
 * sweep (expireStaleOffers) hasn't run yet.
 */
export async function acceptTripOffer(tripId: string, driverId: string): Promise<Trip | null> {
  // Defense in depth against the narrow race where this driver picked up a
  // delivery in the gap between being offered this ride and accepting it —
  // findNextEligibleDriver already filtered this driver out of contention
  // for any trip if that were true at OFFER time, but time has passed.
  if (await driverHasActiveDelivery(driverId)) return null;

  const { count } = await prisma.trip.updateMany({
    where: { id: tripId, status: "OFFERED", driverId, offerExpiresAt: { gt: new Date() } },
    data: { status: "MATCHED", offerExpiresAt: null },
  });
  if (count === 0) return null;

  const trip = await prisma.trip.findUniqueOrThrow({
    where: { id: tripId },
    include: { rider: true, driver: { include: { user: true, vehicles: true } } },
  });
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  await notifyUser(
    trip.riderId,
    "RIDE_DRIVER_ASSIGNED",
    "Driver assigned",
    "A driver has accepted your ride.",
    { type: "TRIP", id: trip.id },
  );
  return trip;
}

/**
 * Driver declines an OFFERED trip. Same atomic-updateMany pattern as accept
 * — a decline racing an expiry or another decline can only apply once.
 * Releases the trip back to REQUESTED (never straight to CANCELLED — a
 * driver declining is not the rider's problem, see P0 special requirement:
 * "do not simply cancel the rider's trip when a driver declines"), records
 * the decline so this driver is never re-offered the same trip, and
 * immediately tries to re-offer it to the next eligible driver.
 */
export async function declineTripOffer(tripId: string, driverId: string): Promise<boolean> {
  const { count } = await prisma.trip.updateMany({
    where: { id: tripId, status: "OFFERED", driverId },
    data: {
      status: "REQUESTED",
      driverId: null,
      offerExpiresAt: null,
      declinedDriverIds: { push: driverId },
    },
  });
  if (count === 0) return false;

  await matchDriverToTrip(tripId);
  return true;
}

/**
 * Release any OFFERED trip whose offer window has passed, and try to
 * re-offer it. Run on a short interval (see index.ts's startOfferExpirySweep)
 * so an unresponsive driver never silently strands a rider — this is the
 * fallback for the case where the driver never explicitly declines at all.
 */
export async function expireStaleOffers(): Promise<void> {
  const stale = await prisma.trip.findMany({
    where: { status: "OFFERED", offerExpiresAt: { lte: new Date() } },
    select: { id: true, driverId: true },
  });
  for (const { id, driverId } of stale) {
    if (!driverId) continue;
    const { count } = await prisma.trip.updateMany({
      where: { id, status: "OFFERED", driverId, offerExpiresAt: { lte: new Date() } },
      data: { status: "REQUESTED", driverId: null, offerExpiresAt: null, declinedDriverIds: { push: driverId } },
    });
    if (count > 0) await matchDriverToTrip(id);
  }
}

/** setInterval handle so callers (only index.ts, today) can clear it if ever needed. */
export function startOfferExpirySweep(intervalMs = 5000): ReturnType<typeof setInterval> {
  return setInterval(() => {
    expireStaleOffers().catch((err) => console.error("Failed to expire stale trip offers", err));
  }, intervalMs);
}

// A REQUESTED trip is only ever offered once, synchronously, at creation
// time (POST /trips) or when released back to REQUESTED by a decline/expiry
// with nobody left to re-offer to. So a rider whose request found nobody
// online stayed stuck on REQUESTED forever, even once a driver went online
// moments later, despite SearchDriverScreen's own copy in user_app claiming
// "we'll keep trying." Bounded to recent requests so coming online doesn't
// reach back and assign someone a ride from an hour ago that the rider has
// long since given up on and left the screen for.
export const PENDING_TRIP_RETRY_WINDOW_MINUTES = 10;

/**
 * Called when a driver goes online (PATCH /drivers/me/availability) — the
 * moment a new offer becomes possible. Sweeps recent REQUESTED trips oldest
 * first and retries matchDriverToTrip on each. Fire-and-forget from the
 * caller — a driver's own "go online" action must never block on this.
 */
export async function matchPendingTrips(): Promise<void> {
  const cutoff = new Date(Date.now() - PENDING_TRIP_RETRY_WINDOW_MINUTES * 60_000);
  const pending = await prisma.trip.findMany({
    where: { status: "REQUESTED", requestedAt: { gte: cutoff } },
    orderBy: { requestedAt: "asc" },
    select: { id: true },
  });
  for (const { id } of pending) {
    await matchDriverToTrip(id);
  }
}
