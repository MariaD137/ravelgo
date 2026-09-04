import { prisma } from "../db/prisma";

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
