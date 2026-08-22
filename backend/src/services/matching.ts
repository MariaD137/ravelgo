import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { DriverBusyConflict, reserveDriver } from "./driver-availability";

/**
 * Synchronous, best-effort matching: find one ACTIVE driver with no
 * conflicting active work — across Ride, Courier, and Rental, not just
 * Ride's own Trip table (see DriverAssignment's doc comment in
 * schema.prisma for why this is one shared table rather than three routes
 * each guessing at each other's state) — and assign them. Runs inline
 * inside `POST /trips` rather than on a queue/worker — the right starting
 * point for the traffic this MVP actually has today. The real trigger to
 * move this to a queue (SQS + a worker, or a scheduled retry for unmatched
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
 * The read (which driver/vehicle is free), the Trip update, and the
 * DriverAssignment reservation all run inside one SERIALIZABLE transaction
 * so two concurrent calls can't both read the same available driver before
 * either writes — Postgres aborts the loser with a serialization failure
 * instead of letting both succeed and double-book the driver.
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
            // Backward-compatible with Trip rows written before
            // DriverAssignment existed (a driver mid-ride from before this
            // migration has no DriverAssignment row yet) as well as the
            // unified check going forward.
            tripsAsDriver: { none: { status: { in: ["MATCHED", "IN_PROGRESS"] } } },
            assignments: { none: { status: "ACTIVE" } },
          },
          orderBy: { rating: "desc" },
        });
        if (!driver) return null;

        // Prefer the driver's primary vehicle; fall back to any other of
        // their vehicles not already committed elsewhere. A driver with no
        // vehicle on file at all (incomplete profile) still gets matched —
        // Trip.vehicleId stays null rather than inventing a vehicle that
        // doesn't exist (see schema.prisma's comment on Trip.vehicleId).
        const vehicle = await tx.vehicle.findFirst({
          where: { driverId: driver.id, assignments: { none: { status: "ACTIVE" } } },
          orderBy: { isPrimary: "desc" },
        });

        const updated = await tx.trip.update({
          where: { id: tripId },
          data: { driverId: driver.id, vehicleId: vehicle?.id, status: "MATCHED" },
        });

        await reserveDriver(tx, {
          driverId: driver.id,
          assignmentType: "RIDE",
          assignmentId: updated.id,
          vehicleId: vehicle?.id,
        });

        return updated;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    // P2034: a concurrent transaction won the race for the same driver and
    // Postgres aborted this one. DriverBusyConflict: the defense-in-depth
    // check inside reserveDriver caught a conflict the driver query above
    // should have already excluded (belt-and-suspenders, not expected in
    // practice under Serializable isolation). Both are treated the same as
    // "no driver was available this attempt" — the trip is left REQUESTED,
    // exactly like the no-driver-available case above, rather than
    // surfacing a 500.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      return null;
    }
    if (err instanceof DriverBusyConflict) {
      return null;
    }
    throw err;
  }
}
