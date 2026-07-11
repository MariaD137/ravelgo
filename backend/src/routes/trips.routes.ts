import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

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
  res.status(201).json(trip);
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
  res.json(trip);
});

// Admin: monitor all trips
tripsRouter.get("/trips", requireAuth, requireRole("Admin"), async (_req, res) => {
  const trips = await prisma.trip.findMany({
    include: { rider: true, driver: { include: { user: true } } },
    orderBy: { requestedAt: "desc" },
    take: 100,
  });
  res.json(trips);
});
