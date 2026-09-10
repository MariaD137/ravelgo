import type { TripStatus } from "@prisma/client";

/**
 * The trip state machine (P0 #9). Before this existed the status handler wrote
 * any value from any current state, so a driver could jump REQUESTED→COMPLETED
 * and bill a trip that was never driven, or resurrect a CANCELLED trip. The
 * backend is now authoritative: only the transitions below are legal.
 *
 * States: REQUESTED → OFFERED (a specific driver has this trip pending their
 * accept/decline, see services/matching.ts) → MATCHED (that driver accepted)
 * → IN_PROGRESS → COMPLETED, with CANCELLED and DISPUTED as side exits.
 * OFFERED→REQUESTED is the decline/expiry path (matching.ts re-offers to the
 * next eligible driver from there) — it is not reachable through this
 * PATCH /trips/:id/status route at all; only through POST
 * /trips/:id/accept|decline, which apply it via their own atomic conditional
 * update, precisely so a driver can never "PATCH" their way around a race.
 */
export const TRIP_TRANSITIONS: Record<TripStatus, TripStatus[]> = {
  REQUESTED: ["OFFERED", "CANCELLED"],
  OFFERED: ["MATCHED", "REQUESTED", "CANCELLED"],
  MATCHED: ["IN_PROGRESS", "CANCELLED", "DISPUTED"],
  IN_PROGRESS: ["COMPLETED", "CANCELLED", "DISPUTED"],
  // A completed trip is terminal except that it can still be disputed.
  COMPLETED: ["DISPUTED"],
  CANCELLED: [],
  // Admin dispute resolution can close a dispute either way.
  DISPUTED: ["COMPLETED", "CANCELLED"],
};

/** True when `to` is a legal next status from `from`. Same status is a no-op reject. */
export function isValidTransition(from: TripStatus, to: TripStatus): boolean {
  return TRIP_TRANSITIONS[from]?.includes(to) ?? false;
}

/**
 * Which transitions a non-Admin DRIVER may perform. Drivers drive the normal
 * forward flow and may cancel a trip they haven't started; everything else
 * (dispute handling, backward moves) is Admin-only. Admins are still bounded by
 * the transition matrix above — they cannot, e.g., move COMPLETED→IN_PROGRESS.
 */
const DRIVER_ALLOWED: ReadonlyArray<[TripStatus, TripStatus]> = [
  ["MATCHED", "IN_PROGRESS"],
  ["IN_PROGRESS", "COMPLETED"],
  ["MATCHED", "CANCELLED"],
];

export function driverMayTransition(from: TripStatus, to: TripStatus): boolean {
  return DRIVER_ALLOWED.some(([f, t]) => f === from && t === to);
}

/** A rider may cancel their own trip only before it is under way. */
export function riderMayCancel(from: TripStatus): boolean {
  return from === "REQUESTED" || from === "OFFERED" || from === "MATCHED";
}
