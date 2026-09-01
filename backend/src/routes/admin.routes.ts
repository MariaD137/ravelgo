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
