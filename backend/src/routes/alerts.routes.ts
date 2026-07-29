import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const alertsRouter = Router();

const createAlertSchema = z.object({
  type: z.enum(["SOS", "FRAUD_SUSPECTED"]),
  tripId: z.string().optional(),
  message: z.string().optional(),
});

// Any authenticated user: raise an emergency/fraud alert, optionally tied to a trip
alertsRouter.post("/emergency-alerts", requireAuth, async (req, res) => {
  const parsed = createAlertSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const alert = await prisma.emergencyAlert.create({
    data: { ...parsed.data, userId: user.id },
  });
  res.status(201).json(alert);
});

// Caller: view my own alerts
alertsRouter.get("/emergency-alerts/mine", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const alerts = await prisma.emergencyAlert.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: "desc" },
  });
  res.json(alerts);
});

// Admin: list all alerts, most urgent (open) first
alertsRouter.get("/emergency-alerts", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [alerts, total] = await Promise.all([
    prisma.emergencyAlert.findMany({
      include: { user: true, trip: true },
      orderBy: [{ status: "asc" }, { createdAt: "desc" }],
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.emergencyAlert.count(),
  ]);
  res.json(paginate(alerts, total, page, pageSize));
});

const statusSchema = z.object({ status: z.enum(["ACKNOWLEDGED", "RESOLVED"]) });

// Admin: acknowledge or resolve an alert
alertsRouter.patch("/emergency-alerts/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const alert = await prisma.emergencyAlert.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      resolvedAt: parsed.data.status === "RESOLVED" ? new Date() : undefined,
    },
  });
  res.json(alert);
});
