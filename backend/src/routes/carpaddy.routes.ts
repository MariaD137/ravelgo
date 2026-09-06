import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const carPaddyRouter = Router();

const submitSchema = z.object({
  plateNumber: z.string().min(1),
});

// Driver: submit a Car Paddy (vehicle license renewal) request. Gated on the
// same admin-approved ACTIVE status as ride/delivery matching and rental
// listing — a PENDING_REVIEW driver isn't yet an approved provider.
carPaddyRouter.post("/car-paddy", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = submitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  if (driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account must be approved before you can submit a Car Paddy request." });
  }

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

// Admin (Super Admin / Operations Manager): approve/reject a Car Paddy request
carPaddyRouter.patch("/car-paddy/:id", requireAuth, requireAdminPermission("listings:write"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const request = await prisma.carPaddyRequest.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status, reviewedAt: new Date() },
  });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "CAR_PADDY_REQUEST_REVIEWED",
    entityType: "CarPaddyRequest",
    entityId: request.id,
    metadata: { status: parsed.data.status },
  });
  res.json(request);
});
