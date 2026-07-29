import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { broadcastTripStatus, getLatestDriverLocation } from "../realtime/hub";
import { matchDriverToTrip } from "../services/matching";

export const tripsRouter = Router();

const createTripSchema = z.object({
  pickup: z.string().min(1),
  destination: z.string().min(1),
  estimatedFare: z.number().positive(),
  category: z.string().default("Personal"),
  pickupNote: z.string().optional(),
});

// Rider: request a trip
tripsRouter.post("/trips", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = createTripSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider not found" });

  const trip = await prisma.trip.create({
    data: { ...parsed.data, riderId: rider.id },
  });

  const matched = await matchDriverToTrip(trip.id);
  res.status(201).json(matched ?? trip);
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

// Driver: advance trip status (accept, start, complete)
tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

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
