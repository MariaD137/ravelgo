import { Router } from "express";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { findOwnDriver } from "../services/driver";
import { DriverBusyConflict, requireDriverAvailable, sendDriverBusyResponse } from "../services/driver-availability";
import {
  CourierRequestConflict,
  IllegalCourierTransitionError,
  acceptCourierRequest,
  updateCourierStatus,
} from "../services/courier";
import { FINAL_FARE_MAX_RATIO, FINAL_FARE_MIN_RATIO } from "../services/pricing";

export const courierRouter = Router();

const createCourierSchema = z.object({
  pickupAddress: z.string().min(1),
  dropoffAddress: z.string().min(1),
  packageDescription: z.string().min(1),
  recipientName: z.string().min(1),
  recipientPhone: z.string().min(1),
  estimatedFare: z.number().positive(),
});

// Rider: request a courier/package delivery
courierRouter.post("/courier-requests", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = createCourierSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  // Same guard as POST /trips: a double-tap or client retry with no check
  // here would create two independent CourierRequest rows for what was
  // meant to be one delivery request.
  const openRequest = await prisma.courierRequest.findFirst({
    where: { senderId: sender.id, status: { in: ["REQUESTED", "MATCHED", "IN_TRANSIT"] } },
  });
  if (openRequest) {
    return res
      .status(409)
      .json({ error: "You already have an active courier request", courierRequestId: openRequest.id });
  }

  try {
    const request = await prisma.courierRequest.create({
      data: { ...parsed.data, senderId: sender.id },
    });
    res.status(201).json(request);
  } catch (err) {
    // Database-level backstop for the same race the `openRequest` check
    // above closes at the application level: a partial unique index
    // (CourierRequest_senderId_open_unique) rejects a second concurrent
    // insert that both requests' `openRequest` reads missed, so the loser
    // gets a clean 409 here instead of two open requests for one sender.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
      return res.status(409).json({ error: "You already have an active courier request" });
    }
    throw err;
  }
});

// Rider: my own courier request history. Registered before "/courier-requests/:id"
// below — same ordering fix as "/trips/mine" vs "/trips/:id".
courierRouter.get("/courier-requests/mine", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  const where = { senderId: sender.id };
  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      where,
      include: { driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});

// Driver: view unassigned courier requests to accept
courierRouter.get("/courier-requests/available", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;
  const where = { status: "REQUESTED" as const, driverId: null };

  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      where,
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});

// Driver: accept a courier request. requireDriverAvailable is a fast-path
// check (rejects a driver already known to be busy, attaches req.driver);
// the actual race-safety comes from acceptCourierRequest's own SERIALIZABLE
// transaction, which re-checks and reserves the driver atomically alongside
// claiming the request — see services/courier.ts's doc comment.
courierRouter.patch(
  "/courier-requests/:id/accept",
  requireAuth,
  requireRole("Driver"),
  requireDriverAvailable,
  async (req, res) => {
    const existing = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: "Courier request not found" });

    try {
      const request = await acceptCourierRequest(req.driver!.id, req.params.id);
      res.json(request);
    } catch (err) {
      if (err instanceof CourierRequestConflict) {
        return res.status(409).json({ error: err.message });
      }
      if (err instanceof DriverBusyConflict) {
        return sendDriverBusyResponse(res, err);
      }
      throw err;
    }
  },
);

const updateStatusSchema = z.object({
  status: z.enum(["IN_TRANSIT", "DELIVERED", "CANCELLED"]),
  finalFare: z.number().positive().optional(),
});

// Driver assigned to it, or Admin: advance courier status
courierRouter.patch("/courier-requests/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Courier request not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver || existing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to update this request" });
    }
  }

  // Same server-side bound as PATCH /trips/:id/status applies to a
  // driver-submitted finalFare — without it a driver could set
  // finalFare to an arbitrary number unrelated to the request's own
  // estimatedFare. Not currently wired into any billing/charge path, but
  // this value is already returned to riders/Admin as the recorded price
  // for the delivery, so bounding it now avoids it becoming an exploitable
  // gap the moment courier billing is added.
  if (parsed.data.status === "DELIVERED" && parsed.data.finalFare != null) {
    const min = existing.estimatedFare * FINAL_FARE_MIN_RATIO;
    const max = existing.estimatedFare * FINAL_FARE_MAX_RATIO;
    if (parsed.data.finalFare < min || parsed.data.finalFare > max) {
      return res.status(400).json({
        error: `finalFare (${parsed.data.finalFare}) must be between ${min} and ${max} (${FINAL_FARE_MIN_RATIO}x-${FINAL_FARE_MAX_RATIO}x the request's estimatedFare of ${existing.estimatedFare})`,
      });
    }
  }

  try {
    const request = await updateCourierStatus(req.params.id, parsed.data);
    res.json(request);
  } catch (err) {
    if (err instanceof IllegalCourierTransitionError) {
      return res.status(409).json({ error: err.message });
    }
    throw err;
  }
});

// Rider or Driver: view a courier request they're party to
courierRouter.get("/courier-requests/:id", requireAuth, async (req, res) => {
  const request = await prisma.courierRequest.findUnique({
    where: { id: req.params.id },
    include: { sender: true, driver: { include: { user: true } } },
  });
  if (!request) return res.status(404).json({ error: "Courier request not found" });

  const groups = req.user!.groups;
  const isOwner =
    request.sender.cognitoSub === req.user!.sub || request.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !groups.includes("Admin")) {
    return res.status(403).json({ error: "Not authorized to view this request" });
  }
  res.json(request);
});

// Admin: monitor all courier requests
courierRouter.get("/courier-requests", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      include: { sender: true, driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count(),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});
