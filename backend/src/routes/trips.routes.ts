import { Router } from "express";
import { z } from "zod";
import { Prisma, type TripStatus } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { broadcastDriverAssignment, broadcastTripStatus, getLatestDriverLocation } from "../realtime/hub";
import { matchDriverToTrip } from "../services/matching";
import { findOwnDriver } from "../services/driver";
import { releaseDriver } from "../services/driver-availability";
import {
  FINAL_FARE_MAX_RATIO,
  FINAL_FARE_MIN_RATIO,
  computeFare,
  getActivePricingRule,
  getSurgeMultiplier,
} from "../services/pricing";

// Terminal Trip statuses: once reached, the driver is no longer
// operationally occupied by this ride and their DriverAssignment (if any)
// is released so they can be matched to a new ride, or accept a courier
// request/rental, again.
const TERMINAL_TRIP_STATUSES = ["COMPLETED", "CANCELLED", "DISPUTED"] as const;

class IllegalTripTransitionError extends Error {
  constructor(from: string, to: string) {
    super(`Trip cannot move from ${from} to ${to}`);
    this.name = "IllegalTripTransitionError";
  }
}

export const tripsRouter = Router();

const createTripSchema = z.object({
  pickup: z.string().min(1),
  destination: z.string().min(1),
  // Legacy/fallback input, used only when distanceKm+durationMinutes aren't
  // given (see the fare-resolution comment below).
  estimatedFare: z.number().positive().optional(),
  // When provided, the fare is computed server-side from the active
  // PricingRule/SurgeZone (the same engine GET /pricing/quote uses) instead
  // of trusting the client's estimatedFare.
  distanceKm: z.number().nonnegative().optional(),
  durationMinutes: z.number().nonnegative().optional(),
  zone: z.string().optional(),
  category: z.string().default("Personal"),
  pickupNote: z.string().optional(),
});

// Rider: request a trip
tripsRouter.post("/trips", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = createTripSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { pickup, destination, category, pickupNote, distanceKm, durationMinutes, zone } = parsed.data;

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider not found" });

  // A double-tap on "Request Ride" (or a client retry) with no guard here
  // would create two independent Trip rows, each independently run through
  // matchDriverToTrip below — the rider could end up matched to two
  // different drivers for what was meant to be one ride request.
  const openTrip = await prisma.trip.findFirst({
    where: { riderId: rider.id, status: { in: ["REQUESTED", "MATCHED", "IN_PROGRESS"] } },
  });
  if (openTrip) {
    return res.status(409).json({ error: "You already have an active trip request", tripId: openTrip.id });
  }

  // Fare resolution, server-authoritative wherever the engine has enough
  // data to be: if the client sent distance/duration (the same inputs
  // GET /pricing/quote takes), recompute the fare server-side and ignore
  // whatever estimatedFare the client sent. Otherwise fall back to the
  // client-supplied estimatedFare, but reject one that's materially below
  // what the active pricing rule's flat base fare alone would cost — the
  // one check possible without distance data. With no PricingRule
  // configured at all, there's nothing to validate against, so the
  // client's value is accepted as before.
  let estimatedFare: number;
  if (distanceKm != null && durationMinutes != null) {
    const rule = await getActivePricingRule();
    if (!rule) return res.status(409).json({ error: "No active pricing rule configured" });
    const { multiplier } = await getSurgeMultiplier(zone);
    estimatedFare = computeFare(rule, distanceKm, durationMinutes, multiplier);
  } else {
    if (parsed.data.estimatedFare == null) {
      return res.status(400).json({
        error: "estimatedFare is required when distanceKm/durationMinutes are not provided",
      });
    }
    const rule = await getActivePricingRule();
    if (rule && parsed.data.estimatedFare < rule.baseFare) {
      return res.status(400).json({
        error: `estimatedFare (${parsed.data.estimatedFare}) is below the active pricing rule's base fare (${rule.baseFare})`,
      });
    }
    estimatedFare = parsed.data.estimatedFare;
  }

  let trip;
  try {
    trip = await prisma.trip.create({
      data: { pickup, destination, category, pickupNote, estimatedFare, riderId: rider.id },
    });
  } catch (err) {
    // Database-level backstop for the same race the `openTrip` check above
    // closes at the application level: a partial unique index
    // (Trip_riderId_open_unique) rejects a second concurrent insert that
    // both requests' `openTrip` reads missed, so the loser gets a clean 409
    // here instead of two open trips for one rider.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
      return res.status(409).json({ error: "You already have an active trip request" });
    }
    throw err;
  }

  const matched = await matchDriverToTrip(trip.id);
  if (matched?.driverId) {
    // The driver has no "browse and accept" step for a ride — matching is
    // synchronous and server-authoritative above — so this is how they
    // find out at all. Best-effort: driver_app's own polling loop
    // (GET /drivers/me/assignment) is the primary, always-correct
    // mechanism this overlays, same relationship as trip:status has to the
    // rider's polling in RideSession.
    broadcastDriverAssignment(matched.driverId, "RIDE", matched.id);
  }
  res.status(201).json(matched ?? trip);
});

// Rider or Driver: my own trip history — a driver's "My Trips" screen and a
// rider's trip history both read this same endpoint, scoped to whichever
// side of the trip the caller is on, rather than each having its own
// separate (and inevitably diverging) route. Registered before "/trips/:id"
// below — Express matches path segments in registration order, so ":id"
// would otherwise swallow "mine" (same fix already applied to "/drivers/me"
// vs "/drivers/:id").
tripsRouter.get("/trips/mine", requireAuth, requireRole("Rider", "Driver"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const isDriver = req.user!.groups.includes("Driver");
  let where: { riderId: string } | { driverId: string };
  if (isDriver) {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver) return res.status(404).json({ error: "Driver profile not found" });
    where = { driverId: driver.id };
  } else {
    const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
    if (!rider) return res.status(404).json({ error: "Rider not found" });
    where = { riderId: rider.id };
  }

  const [trips, total] = await Promise.all([
    prisma.trip.findMany({
      where,
      include: { rider: true, driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.trip.count({ where }),
  ]);
  res.json(paginate(trips, total, page, pageSize));
});

// Rider or Driver: view a trip they're party to
tripsRouter.get("/trips/:id", requireAuth, async (req, res) => {
  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true, driver: { include: { user: true } } },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const groups = req.user!.groups;
  const isOwner =
    trip.rider.cognitoSub === req.user!.sub || trip.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !groups.includes("Admin")) {
    return res.status(403).json({ error: "Not authorized to view this trip" });
  }
  res.json(trip);
});

const updateStatusSchema = z.object({
  status: z.enum(["MATCHED", "IN_PROGRESS", "COMPLETED", "CANCELLED", "DISPUTED"]),
  finalFare: z.number().positive().optional(),
});

// Legal predecessor statuses for each status this endpoint can set — a
// terminal status (COMPLETED/CANCELLED/DISPUTED) never appears as a "from"
// anywhere, so once reached it's final; REQUESTED only ever advances to
// MATCHED, never skips straight to IN_PROGRESS/COMPLETED. DISPUTED is
// reachable from COMPLETED too (a rider contesting a completed trip's
// fare), not just from an in-flight one.
const TRIP_ALLOWED_FROM: Record<string, readonly TripStatus[]> = {
  MATCHED: ["REQUESTED"],
  IN_PROGRESS: ["MATCHED"],
  COMPLETED: ["MATCHED", "IN_PROGRESS"],
  CANCELLED: ["REQUESTED", "MATCHED", "IN_PROGRESS"],
  DISPUTED: ["MATCHED", "IN_PROGRESS", "COMPLETED"],
};

// Driver (must be the trip's assigned driver) or Admin: advance trip status
// (accept, start, complete). Same ownership-check shape already used for
// PATCH /courier-requests/:id/status below.
tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Trip not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver || existing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to update this trip" });
    }
  }

  // Server-side bound on a driver-submitted finalFare, so it can't be set
  // to an arbitrary number unrelated to the trip's own server-established
  // estimatedFare before it reaches billing (POST /trips/:id/charge reads
  // finalFare directly). See FINAL_FARE_MIN_RATIO/MAX_RATIO's doc comment
  // for why this is a ratio against the estimate rather than an exact
  // recomputation.
  if (parsed.data.status === "COMPLETED" && parsed.data.finalFare != null) {
    const min = existing.estimatedFare * FINAL_FARE_MIN_RATIO;
    const max = existing.estimatedFare * FINAL_FARE_MAX_RATIO;
    if (parsed.data.finalFare < min || parsed.data.finalFare > max) {
      return res.status(400).json({
        error: `finalFare (${parsed.data.finalFare}) must be between ${min} and ${max} (${FINAL_FARE_MIN_RATIO}x-${FINAL_FARE_MAX_RATIO}x the trip's estimatedFare of ${existing.estimatedFare})`,
      });
    }
  }

  let trip;
  try {
    trip = await prisma.$transaction(async (tx) => {
      // Atomic conditional update: the "still in a status this target is
      // legally reachable from" check and the write happen in one
      // statement, so a concurrent second request (or a stale client
      // retrying an already-applied transition) can't sneak an illegal
      // transition through between this route's earlier reads and this
      // write — same pattern as the courier/rental accept flows.
      const { count } = await tx.trip.updateMany({
        where: { id: req.params.id, status: { in: [...TRIP_ALLOWED_FROM[parsed.data.status]] } },
        data: {
          status: parsed.data.status,
          finalFare: parsed.data.finalFare,
          completedAt: parsed.data.status === "COMPLETED" ? new Date() : undefined,
        },
      });
      if (count === 0) {
        throw new IllegalTripTransitionError(existing.status, parsed.data.status);
      }
      const updated = await tx.trip.findUniqueOrThrow({ where: { id: req.params.id } });

      if (
        TERMINAL_TRIP_STATUSES.includes(parsed.data.status as (typeof TERMINAL_TRIP_STATUSES)[number]) &&
        updated.driverId
      ) {
        // updated.driverId (read inside this same transaction, after the
        // conditional update committed) rather than existing.driverId (read
        // before the transaction even opened) — a concurrent match can set
        // driverId between those two reads, and using the stale value here
        // would skip releasing a driver who was actually assigned.
        await releaseDriver(tx, { driverId: updated.driverId, assignmentType: "RIDE", assignmentId: updated.id });
      }

      return updated;
    });
  } catch (err) {
    if (err instanceof IllegalTripTransitionError) {
      return res.status(409).json({ error: err.message });
    }
    throw err;
  }
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  res.json(trip);
});

// Cancellable only before the ride is actually underway — once a driver has
// started the trip, IN_PROGRESS/COMPLETED/DISPUTED, or it's already
// CANCELLED, there's nothing left for the rider to call off.
const CANCELLABLE_TRIP_STATUSES = ["REQUESTED", "MATCHED"] as const;

// Rider: cancel my own trip. Admin cancellation is already covered by the
// existing PATCH /trips/:id/status (CANCELLED is one of its allowed
// statuses), so that admin path is untouched.
tripsRouter.patch("/trips/:id/cancel", requireAuth, requireRole("Rider"), async (req, res) => {
  const trip = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider || trip.riderId !== rider.id) {
    return res.status(403).json({ error: "Not authorized to cancel this trip" });
  }

  let updated;
  try {
    updated = await prisma.$transaction(async (tx) => {
      // Same atomic conditional-update pattern as PATCH /trips/:id/status:
      // the "still cancellable" check and the write happen in one
      // statement, so a concurrent match (REQUESTED -> MATCHED, assigning a
      // driver) between this route's earlier read and this write can't
      // silently be overwritten by an unconditional update — and, just as
      // importantly, releaseDriver below reads driverId from this
      // transaction's own post-update row, not the pre-transaction
      // snapshot, so a driver assigned in that race is still released
      // instead of being left orphaned as ACTIVE forever.
      const { count } = await tx.trip.updateMany({
        where: { id: req.params.id, status: { in: [...CANCELLABLE_TRIP_STATUSES] } },
        data: { status: "CANCELLED" },
      });
      if (count === 0) {
        throw new IllegalTripTransitionError(trip.status, "CANCELLED");
      }
      const cancelled = await tx.trip.findUniqueOrThrow({ where: { id: req.params.id } });
      if (cancelled.driverId) {
        await releaseDriver(tx, { driverId: cancelled.driverId, assignmentType: "RIDE", assignmentId: cancelled.id });
      }
      return cancelled;
    });
  } catch (err) {
    if (err instanceof IllegalTripTransitionError) {
      return res.status(409).json({ error: `Trip cannot be cancelled from status ${trip.status}` });
    }
    throw err;
  }
  broadcastTripStatus(updated.id, updated.status, updated.finalFare);
  res.json(updated);
});

// Rider or Driver: poll the assigned driver's last known location (a
// fallback for clients not holding a live WebSocket connection — see
// docs/realtime-architecture.md). 404s until the driver has sent at least
// one location update over WS.
tripsRouter.get("/trips/:id/driver-location", requireAuth, async (req, res) => {
  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true, driver: { include: { user: true } } },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const groups = req.user!.groups;
  const isOwner =
    trip.rider.cognitoSub === req.user!.sub || trip.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !groups.includes("Admin")) {
    return res.status(403).json({ error: "Not authorized to view this trip" });
  }

  if (!trip.driverId) return res.status(404).json({ error: "No driver assigned yet" });
  const location = getLatestDriverLocation(trip.driverId);
  if (!location) return res.status(404).json({ error: "No location reported yet" });
  res.json(location);
});

// Admin: monitor all trips
tripsRouter.get("/trips", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [trips, total] = await Promise.all([
    prisma.trip.findMany({
      include: { rider: true, driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.trip.count(),
  ]);
  res.json(paginate(trips, total, page, pageSize));
});
