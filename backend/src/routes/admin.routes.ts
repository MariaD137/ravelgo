import { Router } from "express";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const adminRouter = Router();

// Admin: dashboard KPIs
adminRouter.get("/admin/dashboard", requireAuth, requireRole("Admin"), async (_req, res) => {
  const [activeTrips, onlineDrivers, pendingDocs, pendingCarPaddy] = await Promise.all([
    prisma.trip.count({ where: { status: { in: ["MATCHED", "IN_PROGRESS"] } } }),
    // "Online" now means approved AND currently online (see Driver.isOnline).
    prisma.driver.count({ where: { status: "ACTIVE", isOnline: true } }),
    prisma.driverDocument.count({ where: { status: "PENDING" } }),
    prisma.carPaddyRequest.count({ where: { status: { in: ["SUBMITTED", "IN_REVIEW"] } } }),
  ]);

  res.json({
    activeTrips,
    onlineDrivers,
    pendingApprovals: pendingDocs + pendingCarPaddy,
  });
});

const MS_PER_DAY = 24 * 60 * 60 * 1000;

// Admin: real ride-revenue and completed-trips aggregates for the last 7
// days, bucketed by day. There's no tracked "driver online hours" anywhere
// in the schema, so that metric is intentionally not returned rather than
// fabricated — the admin UI should say so instead of showing a fake number.
adminRouter.get("/admin/analytics", requireAuth, requireRole("Admin"), async (_req, res) => {
  const days = 7;
  const end = new Date();
  end.setHours(0, 0, 0, 0);
  end.setDate(end.getDate() + 1); // exclusive upper bound: start of tomorrow
  const start = new Date(end.getTime() - days * MS_PER_DAY);

  const [payments, trips] = await Promise.all([
    prisma.payment.findMany({
      where: { status: "SUCCEEDED", paidAt: { gte: start, lt: end } },
      select: { amount: true, paidAt: true },
    }),
    prisma.trip.findMany({
      where: { status: "COMPLETED", completedAt: { gte: start, lt: end } },
      select: { completedAt: true },
    }),
  ]);

  const buckets = Array.from({ length: days }, (_, i) => {
    const date = new Date(start.getTime() + i * MS_PER_DAY);
    return { date: date.toISOString().slice(0, 10), revenue: 0, completedTrips: 0 };
  });
  const bucketIndex = (d: Date) => Math.floor((d.getTime() - start.getTime()) / MS_PER_DAY);

  for (const p of payments) {
    const idx = p.paidAt ? bucketIndex(p.paidAt) : -1;
    if (idx >= 0 && idx < days) buckets[idx].revenue += p.amount;
  }
  for (const t of trips) {
    const idx = t.completedAt ? bucketIndex(t.completedAt) : -1;
    if (idx >= 0 && idx < days) buckets[idx].completedTrips += 1;
  }

  res.json({ days: buckets });
});

// Admin: audit log of privileged actions, newest first.
adminRouter.get("/admin/audit", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [entries, total] = await Promise.all([
    prisma.auditLog.findMany({
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.auditLog.count(),
  ]);
  res.json(paginate(entries, total, page, pageSize));
});
