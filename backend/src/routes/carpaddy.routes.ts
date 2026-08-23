import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { findOwnDriver } from "../services/driver";

export const carPaddyRouter = Router();

const submitSchema = z.object({
  plateNumber: z.string().min(1),
});

// Driver: submit a Car Paddy (vehicle license renewal) request
carPaddyRouter.post("/car-paddy", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = submitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const request = await prisma.carPaddyRequest.create({
    data: { driverId: driver.id, plateNumber: parsed.data.plateNumber },
  });
  res.status(201).json(request);
});

// Admin: list all Car Paddy requests
carPaddyRouter.get("/car-paddy", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [requests, total] = await Promise.all([
    prisma.carPaddyRequest.findMany({
      include: { driver: { include: { user: true } } },
      orderBy: { submittedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.carPaddyRequest.count(),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});

const decisionSchema = z.object({
  status: z.enum(["APPROVED", "REJECTED"]),
});

// A request only moves out of SUBMITTED/IN_REVIEW once — re-approving an
// already-decided request, or flipping an APPROVED one to REJECTED after
// the fact, is not a legal transition. Matches the terminal-state
// protection every other status-patch endpoint in this codebase applies
// (trips, courier requests, rental listings/bookings).
const CAR_PADDY_DECIDABLE_FROM = ["SUBMITTED", "IN_REVIEW"] as const;

// Admin: approve/reject a Car Paddy request
carPaddyRouter.patch("/car-paddy/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { count } = await prisma.carPaddyRequest.updateMany({
    where: { id: req.params.id, status: { in: [...CAR_PADDY_DECIDABLE_FROM] } },
    data: { status: parsed.data.status, reviewedAt: new Date() },
  });
  if (count === 0) {
    const existing = await prisma.carPaddyRequest.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: "Car Paddy request not found" });
    return res
      .status(409)
      .json({ error: `Car Paddy request cannot move to ${parsed.data.status} from status ${existing.status}` });
  }
  const request = await prisma.carPaddyRequest.findUniqueOrThrow({ where: { id: req.params.id } });
  res.json(request);
});
