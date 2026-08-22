import { Router } from "express";
import { z } from "zod";
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

  const request = await prisma.courierRequest.create({
    data: { ...parsed.data, senderId: sender.id },
  });
  res.status(201).json(request);
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
