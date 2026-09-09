import { prisma } from "../db/prisma";
import { broadcastTripStatus } from "../realtime/hub";
import { notifyUser } from "../lib/notifications";

/**
 * Synchronous, best-effort matching: find one ACTIVE driver with no trip
 * currently MATCHED/IN_PROGRESS, and assign them. Runs inline inside
 * `POST /trips` rather than on a queue/worker — the right starting point
 * for the traffic this MVP actually has today. The real trigger to move
 * this to a queue (SQS + a worker, or a scheduled retry for unmatched
 * trips) is unmatched-trip volume becoming visible in practice, not a
 * hypothetical scale concern now.
 *
 * Deliberately not location-aware yet: there's no driver location in
 * Postgres today (RT-02's location stream is in-memory only, see
 * src/realtime/hub.ts) and no PostGIS/geo index to query against. "First
 * available ACTIVE driver, highest rated" is the honest MVP algorithm this
 * data supports — swap in a real distance-based query once driver location
 * is itself persisted somewhere queryable.
 */
export async function matchDriverToTrip(tripId: string) {
  const trip = await prisma.trip.findUnique({ where: { id: tripId } });
  if (!trip || trip.status !== "REQUESTED") return null;

  const driver = await prisma.driver.findFirst({
    where: {
      status: "ACTIVE",
      isOnline: true,
      tripsAsDriver: { none: { status: { in: ["MATCHED", "IN_PROGRESS"] } } },
    },
    orderBy: { rating: "desc" },
  });
  if (!driver) return null;

  // Include the driver relation on the returned trip so the rider's "driver
  // found" card can render immediately (P0 #8). Without this include the
  // create response carried no driver, so the rider app stayed on the
  // "looking for a driver" spinner even though one was already assigned.
  return prisma.trip.update({
    where: { id: tripId },
    data: { driverId: driver.id, status: "MATCHED" },
    include: { rider: true, driver: { include: { user: true, vehicles: true } } },
  });
}

// A REQUESTED trip is only ever matched once, synchronously, at creation
// time (POST /trips above) — there is no retry. So a rider whose request
// found nobody online stayed stuck on REQUESTED forever, even once a driver
// went online moments later, despite SearchDriverScreen's own copy in
// user_app claiming "we'll keep trying." Bounded to recent requests so
// coming online doesn't reach back and assign someone a ride from an hour
// ago that the rider has long since given up on and left the screen for.
export const PENDING_TRIP_RETRY_WINDOW_MINUTES = 10;

/**
 * Called when a driver goes online (PATCH /drivers/me/availability) — the
 * moment a new match becomes possible. Sweeps recent REQUESTED trips oldest
 * first and retries matchDriverToTrip on each; most of the time this finds
 * either zero or one (the trip this driver themselves can now take), but it
 * isn't bounded to just one so it also recovers any other trip a
 * previously-online driver could have picked up but didn't (e.g. they went
 * online in between two requests). Fire-and-forget from the caller — a
 * driver's own "go online" action must never block on this.
 */
export async function matchPendingTrips(): Promise<void> {
  const cutoff = new Date(Date.now() - PENDING_TRIP_RETRY_WINDOW_MINUTES * 60_000);
  const pending = await prisma.trip.findMany({
    where: { status: "REQUESTED", requestedAt: { gte: cutoff } },
    orderBy: { requestedAt: "asc" },
    select: { id: true },
  });
  for (const { id } of pending) {
    const matched = await matchDriverToTrip(id);
    if (!matched) continue;
    // Same fan-out as the initial synchronous match in POST /trips, plus a
    // WebSocket broadcast — unlike the initial match, the rider's screen is
    // already open and subscribed by now, and won't reload the HTTP response
    // that would otherwise be the only place it learns of a driver.
    broadcastTripStatus(matched.id, matched.status, matched.finalFare);
    await notifyUser(
      matched.riderId,
      "RIDE_DRIVER_ASSIGNED",
      "Driver assigned",
      "A driver has been assigned to your ride.",
      { type: "TRIP", id: matched.id },
    );
  }
}
