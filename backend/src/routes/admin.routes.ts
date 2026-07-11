import { Router } from "express";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

export const adminRouter = Router();

// Admin: dashboard KPIs
adminRouter.get("/admin/dashboard", requireAuth, requireRole("Admin"), async (_req, res) => {
  const [activeTrips, onlineDrivers, pendingDocs, pendingCarPaddy] = await Promise.all([
    prisma.trip.count({ where: { status: { in: ["MATCHED", "IN_PROGRESS"] } } }),
    prisma.driver.count({ where: { status: "ACTIVE" } }),
    prisma.driverDocument.count({ where: { status: "PENDING" } }),
    prisma.carPaddyRequest.count({ where: { status: { in: ["SUBMITTED", "IN_REVIEW"] } } }),
  ]);

  res.json({
    activeTrips,
    onlineDrivers,
    pendingApprovals: pendingDocs + pendingCarPaddy,
  });
});
