import type { RideVehicleClass, Trip } from "@prisma/client";
import { prisma } from "../db/prisma";
import { haversineKm } from "../lib/geo";
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
 * Location-aware (gap B-1): drivers persist their last reported position on
 * their Driver row (services/driver-location.ts, fed by POST
 * /drivers/me/location and the WebSocket location feed). Candidates are the
 * eligible drivers with a position fresher than MATCHING_LOCATION_MAX_AGE_MS,
 * ranked by great-circle distance to the pickup, then rating. A driver who
 * has never reported a position (or whose last report is stale) is never
 * offered a ride they may be nowhere near. The eligible set is small (only
 * online, unassigned, correctly-classed drivers with a fresh location), so
 * ranking in memory with haversine is cheap and needs no PostGIS.
 *
 * If a trip has no pickup coordinates at all (legacy rows only — POST /trips
 * requires them) it falls back to rating order across fresh-located drivers.
 */
export const MATCHING_LOCATION_MAX_AGE_MS = 2 * 60_000;
export const MATCHING_MAX_DISTANCE_KM = 25;

async function findNextEligibleDriver(trip: Trip) {
  let eligibleClasses: RideVehicleClass[] = [];
  if (trip.rideCategoryKey) {
    const category = await prisma.rideCategory.findUnique({ where: { key: trip.rideCategoryKey } });
    eligibleClasses = category?.eligibleVehicleClasses ?? [];
  }

  const freshSince = new Date(Date.now() - MATCHING_LOCATION_MAX_AGE_MS);
  const candidates = await prisma.driver.findMany({
    where: {
      status: "ACTIVE",
      isOnline: true,
      id: { notIn: trip.declinedDriverIds },
      lastLat: { not: null },
      lastLng: { not: null },
      lastLocationAt: { gte: freshSince },
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
  if (candidates.length === 0) return null;

  if (trip.pickupLat == null || trip.pickupLng == null) return candidates[0];
  const pickup = { lat: trip.pickupLat, lng: trip.pickupLng };

  const ranked = candidates
    .map((driver) => ({
      driver,
      distanceKm: haversineKm(pickup, { lat: driver.lastLat as number, lng: driver.lastLng as number }),
    }))
    .filter(({ distanceKm }) => distanceKm <= MATCHING_MAX_DISTANCE_KM)
    .sort((a, b) => a.distanceKm - b.distanceKm || b.driver.rating - a.driver.rating);
  return ranked[0]?.driver ?? null;
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

  // Conditional on the trip still being REQUESTED: matchDriverToTrip can now
  // be triggered concurrently (trip creation, decline/expiry re-offers, a
  // driver going online, and every persisted location ping via
  // maybeMatchPendingTrips), so two callers that both found a driver for the
  // same trip must not both write an offer — only the first wins.
  const { count } = await prisma.trip.updateMany({
    where: { id: tripId, status: "REQUESTED" },
    data: {
      driverId: driver.id,
      status: "OFFERED",
      offerExpiresAt: new Date(Date.now() + OFFER_TTL_SECONDS * 1000),
    },
  });
  if (count === 0) return null;

  const offered = await prisma.trip.findUniqueOrThrow({
    where: { id: tripId },
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

// Location pings arrive every ~20 s per online driver (plus the WebSocket
// feed while on a trip), so a sweep on every persisted ping would be a full
// REQUESTED scan per driver per few seconds. Coalesce: at most one sweep per
// PENDING_MATCH_THROTTLE_MS; a ping that lands inside the window is dropped,
// because the next ping (or the next decline/expiry/go-online) retries anyway.
export const PENDING_MATCH_THROTTLE_MS = 3_000;
let lastPendingSweepAt = 0;
let pendingSweep: Promise<void> | null = null;

/**
 * Throttled matchPendingTrips for high-frequency triggers (driver location
 * persistence). Returns the in-flight sweep so tests can await it; callers in
 * request paths must `void` it.
 */
export function maybeMatchPendingTrips(): Promise<void> {
  if (pendingSweep) return pendingSweep;
  const now = Date.now();
  if (now - lastPendingSweepAt < PENDING_MATCH_THROTTLE_MS) return Promise.resolve();
  lastPendingSweepAt = now;
  pendingSweep = matchPendingTrips()
    .catch((err) => console.error("Failed to match pending trips after location update", err))
    .finally(() => {
      pendingSweep = null;
    });
  return pendingSweep;
}

/** Test hook: forget the pending-sweep throttle. */
export function resetMatchingThrottle(): void {
  lastPendingSweepAt = 0;
}
