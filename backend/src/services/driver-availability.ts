import { AssignmentType, Driver, Prisma } from "@prisma/client";
import type { NextFunction, Request, Response } from "express";
import { prisma } from "../db/prisma";
import { findOwnDriver } from "./driver";

// Prisma.TransactionClient outside a $transaction callback, or the top-level
// `prisma` client itself — every function here works with either, so a
// caller not already inside a transaction (e.g. a plain availability check
// for a UI hint) doesn't have to open one just to call it.
type DbClient = Prisma.TransactionClient | typeof prisma;

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      driver?: Driver;
    }
  }
}

export class DriverBusyConflict extends Error {
  readonly code = "DRIVER_BUSY" as const;
  readonly activeAssignmentType?: AssignmentType;
  readonly activeAssignmentId?: string;

  constructor(message: string, active?: { assignmentType: AssignmentType; assignmentId: string }) {
    super(message);
    this.name = "DriverBusyConflict";
    this.activeAssignmentType = active?.assignmentType;
    this.activeAssignmentId = active?.assignmentId;
  }
}

/** The one active-occupation row for a driver, or null if free. Ride,
 * Courier, and Rental all read this same table instead of each other's. */
export async function getActiveAssignment(client: DbClient, driverId: string) {
  return client.driverAssignment.findFirst({ where: { driverId, status: "ACTIVE" } });
}

export async function isDriverAvailable(client: DbClient, driverId: string): Promise<boolean> {
  return (await getActiveAssignment(client, driverId)) === null;
}

/**
 * Atomically claims a driver for a new assignment. Must be called inside a
 * `prisma.$transaction(..., { isolationLevel: Serializable })` alongside
 * whatever domain write (matching a trip, accepting a courier request,
 * activating a rental) the reservation is for, so the two either both
 * commit or both roll back together.
 *
 * Two layers of protection, deliberately redundant:
 *  1. The pre-check below (getActiveAssignment) gives a clean, fast
 *     DriverBusyConflict in the overwhelmingly common case.
 *  2. The partial unique index on DriverAssignment(driverId) WHERE status =
 *     'ACTIVE' (see this table's migration) is what actually stops two
 *     concurrent reservations for the same driver — Postgres rejects the
 *     loser's INSERT with a unique_violation (P2002) even if the pre-check
 *     above raced and both callers passed it.
 */
export async function reserveDriver(
  tx: Prisma.TransactionClient,
  params: { driverId: string; assignmentType: AssignmentType; assignmentId: string; vehicleId?: string | null },
) {
  const active = await getActiveAssignment(tx, params.driverId);
  if (active) {
    throw new DriverBusyConflict(
      `Driver is currently assigned to an active ${active.assignmentType.toLowerCase()}.`,
      { assignmentType: active.assignmentType, assignmentId: active.assignmentId },
    );
  }

  try {
    return await tx.driverAssignment.create({
      data: {
        driverId: params.driverId,
        assignmentType: params.assignmentType,
        assignmentId: params.assignmentId,
        vehicleId: params.vehicleId ?? null,
      },
    });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
      // The database-level backstop caught a race the pre-check above
      // missed: another transaction committed an ACTIVE row for this
      // driver between our check and our insert.
      throw new DriverBusyConflict("Driver is currently assigned to another active job.");
    }
    throw err;
  }
}

/** Ends the driver's active assignment for a specific domain record, e.g.
 * when a Trip/CourierRequest/RentalBooking reaches a terminal status. A
 * no-op (0 rows) if there was no matching ACTIVE row — safe to call from a
 * status-update path that might run more than once for the same record. */
export async function releaseDriver(
  tx: Prisma.TransactionClient,
  params: { driverId: string; assignmentType: AssignmentType; assignmentId: string },
) {
  await tx.driverAssignment.updateMany({
    where: {
      driverId: params.driverId,
      assignmentType: params.assignmentType,
      assignmentId: params.assignmentId,
      status: "ACTIVE",
    },
    data: { status: "ENDED", endedAt: new Date() },
  });
}

/** Standard 409 body for a driver-busy conflict (Part 25's response shape). */
export function sendDriverBusyResponse(res: Response, err: DriverBusyConflict) {
  res.status(409).json({
    code: err.code,
    message: err.message,
    activeAssignmentType: err.activeAssignmentType,
    activeAssignmentId: err.activeAssignmentId,
  });
}

/**
 * Operational authorization, distinct from requireRole("Driver"): having
 * the Driver role only proves who the caller is, not whether they're free
 * to take on a new assignment right now. Resolves the caller's own Driver
 * row and attaches it to req.driver for the route handler to reuse (no
 * second findOwnDriver lookup needed), then rejects with the standard
 * DRIVER_BUSY shape if they already hold an active assignment.
 *
 * This is a convenience fast-path for callers, not the actual safety
 * boundary — the transaction each route runs (reserveDriver inside a
 * Serializable transaction) is what's race-safe. A driver who passes this
 * check and then loses a concurrent race still gets rejected by
 * reserveDriver inside the transaction.
 */
export async function requireDriverAvailable(req: Request, res: Response, next: NextFunction) {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const active = await getActiveAssignment(prisma, driver.id);
  if (active) {
    return sendDriverBusyResponse(
      res,
      new DriverBusyConflict(`Driver is currently assigned to an active ${active.assignmentType.toLowerCase()}.`, {
        assignmentType: active.assignmentType,
        assignmentId: active.assignmentId,
      }),
    );
  }

  req.driver = driver;
  next();
}
