import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { notifyAllAdmins } from "../lib/notifications";
import { csvList, inFilter, paginate, paginationQuerySchema } from "../lib/pagination";

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
  await notifyAllAdmins(
    "ADMIN_SAFETY_ALERT_RAISED",
    alert.type === "SOS" ? "SOS alert raised" : "Fraud alert raised",
    alert.message || `A ${alert.type === "SOS" ? "safety" : "fraud"} alert was just raised.`,
    { type: "EMERGENCY_ALERT", id: alert.id },
  );
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

const adminAlertsQuerySchema = paginationQuerySchema.extend({
  // The Admin App has one screen per alert type (SOS vs suspected fraud);
  // filtering here means each screen pages through ITS alerts, not through
  // a mixed list it then thins out client-side.
  type: z.enum(["SOS", "FRAUD_SUSPECTED"]).optional(),
  status: z.preprocess(csvList, z.array(z.enum(["OPEN", "ACKNOWLEDGED", "RESOLVED"])).optional()),
});

// Admin: list all alerts, most urgent (open) first
alertsRouter.get("/emergency-alerts", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = adminAlertsQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, type, status } = parsed.data;
  const where = { type, status: inFilter(status) };

  const [alerts, total] = await Promise.all([
    prisma.emergencyAlert.findMany({
      where,
      include: { user: true, trip: true },
      orderBy: [{ status: "asc" }, { createdAt: "desc" }],
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.emergencyAlert.count({ where }),
  ]);
  res.json(paginate(alerts, total, page, pageSize));
});

const statusSchema = z.object({ status: z.enum(["ACKNOWLEDGED", "RESOLVED"]) });

// Admin: acknowledge or resolve an alert
alertsRouter.patch("/emergency-alerts/:id/status", requireAuth, requireAdminPermission("alerts:write"), async (req, res) => {
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
