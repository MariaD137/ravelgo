import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { broadcastFleetEvent, broadcastTripStatus, getLatestDriverLocation } from "../realtime/hub";
import { matchDriverToTrip } from "../services/matching";
import { calculateFinalFare, MAX_TRIP_DISTANCE_KM, MAX_TRIP_DURATION_MINUTES, NoPricingRuleError } from "../services/fare";

export const tripsRouter = Router();

const VALID_TRIP_TRANSITIONS: Record<string, string[]> = {
  REQUESTED: ["MATCHED", "CANCELLED"],
  MATCHED: ["IN_PROGRESS", "CANCELLED"],
  IN_PROGRESS: ["COMPLETED", "CANCELLED", "DISPUTED"],
  COMPLETED: ["DISPUTED"],
  CANCELLED: [],
  DISPUTED: ["COMPLETED", "CANCELLED"],
};

const createTripSchema = z.object({
  pickup: z.string().min(1),
  destination: z.string().min(1),
  estimatedFare: z.number().positive().max(10000),
  category: z.string().default("Personal"),
  pickupNote: z.string().optional(),
});

// Rider: request a trip
tripsRouter.post("/trips", requireAuth, requireRole("Rider"), asyncHandler(async (req, res) => {
  const parsed = createTripSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider not found" });

  const trip = await prisma.trip.create({
    data: { ...parsed.data, riderId: rider.id },
  });

  const matched = await matchDriverToTrip(trip.id);
  res.status(201).json(matched ?? trip);
}));

// Rider or Driver: view a trip they're party to
tripsRouter.get("/trips/:id", requireAuth, asyncHandler(async (req, res) => {
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
}));

const updateStatusSchema = z
  .object({
    status: z.enum(["MATCHED", "IN_PROGRESS", "COMPLETED", "CANCELLED", "DISPUTED"]),
    // Driver-reported completion metrics — the *inputs* to the server-side
    // fare calculation (services/fare.ts), never a dollar amount. The
    // client/driver has no way to submit a fare directly: finalFare is
    // always computed server-side from these against the active
    // PricingRule, so a driver cannot charge more (or less) than the rate
    // card says a trip of this distance/duration costs.
    distanceKm: z.number().positive().max(MAX_TRIP_DISTANCE_KM).optional(),
    durationMinutes: z.number().positive().max(MAX_TRIP_DURATION_MINUTES).optional(),
  })
  .refine((data) => data.status !== "COMPLETED" || data.distanceKm !== undefined, {
    message: "distanceKm is required to complete a trip",
    path: ["distanceKm"],
  })
  .refine((data) => data.status !== "COMPLETED" || data.durationMinutes !== undefined, {
    message: "durationMinutes is required to complete a trip",
    path: ["durationMinutes"],
  });

// Driver: advance trip status (accept, start, complete)
tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), asyncHandler(async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { driver: { include: { user: true } } },
  });
  if (!existing) return res.status(404).json({ error: "Trip not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    if (!existing.driver || existing.driver.user.cognitoSub !== req.user!.sub) {
      return res.status(403).json({ error: "Not authorized to update this trip" });
    }
  }

  const allowed = VALID_TRIP_TRANSITIONS[existing.status] ?? [];
  if (!allowed.includes(parsed.data.status)) {
    return res.status(400).json({
      error: { code: "INVALID_STATUS_TRANSITION", message: `Cannot transition from ${existing.status} to ${parsed.data.status}` },
    });
  }

  let finalFare: number | undefined;
  if (parsed.data.status === "COMPLETED") {
    try {
      finalFare = await calculateFinalFare(parsed.data.distanceKm!, parsed.data.durationMinutes!);
    } catch (err) {
      if (err instanceof NoPricingRuleError) {
        return res.status(409).json({ error: err.message });
      }
      throw err;
    }
  }

  // Conditional update: only applies if the trip's status is still exactly
  // what we read above. Two concurrent requests against the same trip
  // (double-tap, or a driver and an Admin racing) will both pass the
  // checks above, but only the first UPDATE to actually commit satisfies
  // this WHERE clause — Postgres serializes the second one behind the
  // first's row lock, and by the time it re-evaluates, `status` has
  // already moved, so it matches zero rows instead of double-applying the
  // transition (and, for COMPLETED, double-incrementing totalTrips below).
  const { count } = await prisma.trip.updateMany({
    where: { id: req.params.id, status: existing.status },
    data: {
      status: parsed.data.status,
      finalFare,
      distanceKm: parsed.data.distanceKm,
      durationMinutes: parsed.data.durationMinutes,
      completedAt: parsed.data.status === "COMPLETED" ? new Date() : undefined,
    },
  });
  if (count === 0) {
    return res.status(409).json({
      error: { code: "TRIP_STATUS_CHANGED", message: "Trip status changed before this update could apply — reload and retry" },
    });
  }

  if (parsed.data.status === "COMPLETED" && existing.driverId) {
    await prisma.driver.update({
      where: { id: existing.driverId },
      data: { totalTrips: { increment: 1 } },
    });
  }

  const trip = await prisma.trip.findUniqueOrThrow({ where: { id: req.params.id } });
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  if (trip.driverId && trip.status === "IN_PROGRESS") {
    broadcastFleetEvent("driver:trip_started", { driverId: trip.driverId, tripId: trip.id });
  } else if (trip.driverId && trip.status === "COMPLETED") {
    broadcastFleetEvent("driver:trip_completed", { driverId: trip.driverId, tripId: trip.id });
  }
  res.json(trip);
}));

// Rider or Driver: poll the assigned driver's last known location (a
// fallback for clients not holding a live WebSocket connection — see
// docs/realtime-architecture.md). 404s until the driver has sent at least
// one location update over WS.
tripsRouter.get("/trips/:id/driver-location", requireAuth, asyncHandler(async (req, res) => {
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
}));

// Driver: list my assigned trips
tripsRouter.get("/trips/me", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const [trips, total] = await Promise.all([
    prisma.trip.findMany({
      where: { driverId: driver.id },
      include: { rider: { select: { firstName: true, lastName: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.trip.count({ where: { driverId: driver.id } }),
  ]);
  res.json(paginate(trips, total, page, pageSize));
}));

// Rider: rate a completed trip's driver
const ratingSchema = z.object({
  rating: z.number().min(1).max(5),
  comment: z.string().max(500).optional(),
});

tripsRouter.post("/trips/:id/rating", requireAuth, requireRole("Rider"), asyncHandler(async (req, res) => {
  const parsed = ratingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.rider.cognitoSub !== req.user!.sub) return res.status(403).json({ error: "Not your trip" });
  if (trip.status !== "COMPLETED") return res.status(400).json({ error: "Trip must be COMPLETED to rate" });
  if (!trip.driverId) return res.status(400).json({ error: "Trip has no driver" });

  const driver = await prisma.driver.findUnique({ where: { id: trip.driverId } });
  if (!driver) return res.status(404).json({ error: "Driver not found" });

  const newRating = ((driver.rating * driver.totalTrips) + parsed.data.rating) / (driver.totalTrips + 1);
  const updated = await prisma.driver.update({
    where: { id: trip.driverId },
    data: { rating: Math.round(newRating * 100) / 100 },
  });
  res.json({ rating: updated.rating });
}));

// Admin: monitor all trips
tripsRouter.get("/trips", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
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
}));
