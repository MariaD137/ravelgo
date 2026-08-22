import { Prisma } from "@prisma/client";
import type { CourierStatus } from "@prisma/client";
import { prisma } from "../db/prisma";
import { releaseDriver, reserveDriver } from "./driver-availability";

export class CourierRequestConflict extends Error {
  constructor(message = "Request already matched") {
    super(message);
    this.name = "CourierRequestConflict";
  }
}

export class IllegalCourierTransitionError extends Error {
  constructor(from: string, to: string) {
    super(`Courier request cannot move from ${from} to ${to}`);
    this.name = "IllegalCourierTransitionError";
  }
}

// Legal predecessor statuses for each status PATCH .../status can set — a
// terminal status (DELIVERED/CANCELLED) never appears as a "from" anywhere,
// and REQUESTED (unassigned) is never reachable through this endpoint at
// all — claiming a request happens only through acceptCourierRequest above.
const COURIER_ALLOWED_FROM: Record<string, readonly CourierStatus[]> = {
  IN_TRANSIT: ["MATCHED"],
  DELIVERED: ["IN_TRANSIT"],
  CANCELLED: ["MATCHED", "IN_TRANSIT"],
};

/**
 * Accepts a courier request for a driver, atomically. Two protections
 * happen inside the same SERIALIZABLE transaction: (1) the courier request
 * itself can only be claimed once (conditional updateMany, same pattern as
 * before this refactor), and (2) the driver is reserved via the shared
 * DriverAssignment table, so a driver already MATCHED/IN_PROGRESS on a ride
 * (or already MATCHED/IN_TRANSIT on another courier request) is rejected
 * here instead of silently double-booked. If either check loses a race,
 * the whole transaction rolls back — never a courier request left assigned
 * to a driver whose reservation didn't actually succeed.
 */
export async function acceptCourierRequest(driverId: string, requestId: string) {
  try {
    return await prisma.$transaction(
      async (tx) => {
        const { count } = await tx.courierRequest.updateMany({
          where: { id: requestId, status: "REQUESTED", driverId: null },
          data: { driverId, status: "MATCHED" },
        });
        if (count === 0) {
          throw new CourierRequestConflict();
        }

        await reserveDriver(tx, { driverId, assignmentType: "COURIER", assignmentId: requestId });

        return tx.courierRequest.findUniqueOrThrow({ where: { id: requestId } });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      throw new CourierRequestConflict();
    }
    throw err;
  }
}

export interface UpdateCourierStatusInput {
  status: "IN_TRANSIT" | "DELIVERED" | "CANCELLED";
  finalFare?: number;
}

/** Advances a courier request's status and, on a terminal status
 * (DELIVERED/CANCELLED), releases the assigned driver's active assignment
 * so they become available for a new ride/courier/rental again. */
export async function updateCourierStatus(requestId: string, data: UpdateCourierStatusInput) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.courierRequest.findUniqueOrThrow({ where: { id: requestId } });

    // Atomic conditional update, same shape as acceptCourierRequest above:
    // the legal-predecessor check and the write happen in one statement so
    // a concurrent second request can't slip an illegal transition through
    // (e.g. two racing DELIVERED calls both reading IN_TRANSIT before
    // either commits).
    const { count } = await tx.courierRequest.updateMany({
      where: { id: requestId, status: { in: [...COURIER_ALLOWED_FROM[data.status]] } },
      data: {
        status: data.status,
        finalFare: data.finalFare,
        deliveredAt: data.status === "DELIVERED" ? new Date() : undefined,
      },
    });
    if (count === 0) {
      throw new IllegalCourierTransitionError(existing.status, data.status);
    }
    const updated = await tx.courierRequest.findUniqueOrThrow({ where: { id: requestId } });

    if ((data.status === "DELIVERED" || data.status === "CANCELLED") && existing.driverId) {
      await releaseDriver(tx, {
        driverId: existing.driverId,
        assignmentType: "COURIER",
        assignmentId: requestId,
      });
    }

    return updated;
  });
}
