import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { broadcastTripStatus, getLatestDriverLocation } from "../realtime/hub";
import { matchDriverToTrip } from "../services/matching";
import { quoteFare } from "../services/pricing";
import { MAX_FINAL_FARE_MULTIPLIER, MIN_FINAL_FARE_MULTIPLIER, moneyAmountSchema } from "../lib/money";
import { sensitiveLimiter } from "../middleware/rate-limit";

export const tripsRouter = Router();

// The rider supplies the trip inputs (distance/duration/zone) — NOT the fare.
// The fare is computed server-side from the active PricingRule (see
// services/pricing.ts), so a client cannot assert `estimatedFare: 1` (or any
// other value) and have the backend treat it as the agreed price. Distance
// and duration are still client-provided in this MVP because there is no
// routing/geocoding service yet — that is an honest limitation, but the RATE
// applied to them is authoritative and admin-controlled, and baseFare acts as
// a floor even if the client claims a zero-distance trip.
const createTripSchema = z.object({
  pickup: z.string().min(1),
  destination: z.string().min(1),
  distanceKm: z.number().finite().nonnegative().max(2000),
  durationMinutes: z.number().finite().nonnegative().max(1440),
  zone: z.string().min(1).optional(),
  category: z.string().default("Personal"),
  pickupNote: z.string().optional(),
});

// Rider: request a trip
tripsRouter.post("/trips", sensitiveLimiter, requireAuth, requireRole("Rider"), async (req, res, next) => {
  const parsed = createTripSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider not found" });

  // Authoritative fare — never taken from the request body.
  let fare;
  try {
    fare = await quoteFare(parsed.data.distanceKm, parsed.data.durationMinutes, parsed.data.zone);
  } catch (err) {
    return next(err); // 409 when no active pricing rule is configured
  }

  const trip = await prisma.trip.create({
    data: {
      pickup: parsed.data.pickup,
      destination: parsed.data.destination,
      category: parsed.data.category,
      pickupNote: parsed.data.pickupNote,
      estimatedFare: fare.estimatedFare,
      riderId: rider.id,
    },
  });

  const matched = await matchDriverToTrip(trip.id);
  res.status(201).json(matched ?? trip);
});

// Rider or Driver: list the trips I'm party to (as the rider, or as the
// assigned driver). This is what powers a rider's trip history and a driver's
// completed-trips list. Declared before "/trips/:id" so "mine" isn't captured
// as an :id.
tripsRouter.get("/trips/mine", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const where = {
    OR: [
      { rider: { cognitoSub: req.user!.sub } },
      { driver: { user: { cognitoSub: req.user!.sub } } },
    ],
  };

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

const rateSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).optional(),
});

// Rider: rate the driver for a completed trip they own. Recomputes the
// driver's average rating across all their rated trips.
tripsRouter.post("/trips/:id/rating", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = rateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.rider.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to rate this trip" });
  }
  if (trip.status !== "COMPLETED") {
    return res.status(409).json({ error: "You can only rate a completed trip" });
  }
  if (!trip.driverId) {
    return res.status(409).json({ error: "This trip had no driver to rate" });
  }

  const updated = await prisma.trip.update({
    where: { id: trip.id },
    data: { riderRating: parsed.data.rating },
  });

  // Recompute the driver's average rating from all their rated trips.
  const agg = await prisma.trip.aggregate({
    where: { driverId: trip.driverId, riderRating: { not: null } },
    _avg: { riderRating: true },
  });
  if (agg._avg.riderRating != null) {
    await prisma.driver.update({
      where: { id: trip.driverId },
      data: { rating: agg._avg.riderRating },
    });
  }

  res.json(updated);
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
  finalFare: moneyAmountSchema.optional(),
});

// Driver assigned to it, or Admin: advance trip status (accept, start, complete)
tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Trip not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
    if (!driver || existing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to update this trip" });
    }
  }

  // The final fare is what actually gets charged (payments.routes.ts) and
  // paid out (services/payouts.ts). It's set by the driver, so it must be
  // anchored to the server-computed estimate rather than trusted outright:
  // a driver can adjust up for waiting time / a longer route, but not to an
  // arbitrary multiple of the price the rider agreed to. An Admin (dispute
  // resolution, manual correction) is allowed to override outside the band.
  if (parsed.data.finalFare != null && !isAdmin) {
    const lower = existing.estimatedFare * MIN_FINAL_FARE_MULTIPLIER;
    const upper = existing.estimatedFare * MAX_FINAL_FARE_MULTIPLIER;
    if (parsed.data.finalFare < lower || parsed.data.finalFare > upper) {
      return res.status(422).json({
        error: {
          code: "FARE_OUT_OF_RANGE",
          message: `finalFare must be within ${MIN_FINAL_FARE_MULTIPLIER}x–${MAX_FINAL_FARE_MULTIPLIER}x the estimated fare of ${existing.estimatedFare}`,
          timestamp: new Date().toISOString(),
        },
      });
    }
  }

  const trip = await prisma.trip.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      finalFare: parsed.data.finalFare,
      completedAt: parsed.data.status === "COMPLETED" ? new Date() : undefined,
    },
  });
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  res.json(trip);
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
