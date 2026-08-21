import { Prisma } from "@prisma/client";
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
 *
 * The read (which driver is free) and the write (assign them) run inside
 * one SERIALIZABLE transaction so two concurrent calls can't both read the
 * same available driver before either writes — Postgres aborts the loser
 * with a serialization failure instead of letting both succeed and
 * double-book the driver. There's no single boolean on Driver to do a
 * plain conditional UPDATE ... WHERE against (availability depends on the
 * *other* Trip rows tied to that driver), so a transaction is the smallest
 * fix that doesn't require a schema change.
 */
export async function matchDriverToTrip(tripId: string) {
  try {
    return await prisma.$transaction(
      async (tx) => {
        const trip = await tx.trip.findUnique({ where: { id: tripId } });
        if (!trip || trip.status !== "REQUESTED") return null;

        const driver = await tx.driver.findFirst({
          where: {
            status: "ACTIVE",
            tripsAsDriver: { none: { status: { in: ["MATCHED", "IN_PROGRESS"] } } },
          },
          orderBy: { rating: "desc" },
        });
        if (!driver) return null;

        return tx.trip.update({
          where: { id: tripId },
          data: { driverId: driver.id, status: "MATCHED" },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    // P2034: a concurrent transaction won the race for the same driver and
    // Postgres aborted this one. Treated the same as "no driver was
    // available this attempt" — the trip is left REQUESTED, exactly like
    // the no-driver-available case above, rather than surfacing a 500.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      return null;
    }
    throw err;
  }
}
