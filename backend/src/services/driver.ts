import type { DriverStatus } from "@prisma/client";
import { prisma } from "../db/prisma";

// Shared by every route that needs "the Driver row for the caller's own
// Cognito identity" — was duplicated verbatim across courier.routes.ts,
// rentals.routes.ts, vehicles.routes.ts, and inlined again in
// trips.routes.ts before this extraction.
export async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

/**
 * The admin-approval/disable gate: a driver must be ACTIVE to take on new
 * work. Returns a human-readable reason if [status] blocks it, or null if
 * the driver is clear to proceed. Deliberately narrow — it only guards
 * *starting* something new (going online, accepting a courier request,
 * listing/activating a rental), never an already-in-progress job (a status
 * change made mid-job would otherwise strand a rider/renter who's already
 * relying on this driver). Ride matching enforces this independently via
 * matchDriverToTrip's own `status: "ACTIVE"` query filter, not this
 * function — this exists for the routes that don't go through that query.
 */
export function driverActiveStatusError(status: DriverStatus): string | null {
  if (status === "ACTIVE") return null;
  return status === "PENDING_REVIEW"
    ? "Your driver application is still under review"
    : "Your driver account has been suspended";
}
