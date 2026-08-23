import { Router } from "express";
import { z } from "zod";
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

// Real, Postgres-computed weekly figures for the admin Reports screen — no
// invented "driver online hours" metric, since nothing in this schema
// records online-presence duration (Driver.status is an approval state,
// DriverAssignment tracks active jobs, neither is "online time"). Only
// report numbers this schema can actually answer.
adminRouter.get("/admin/reports/weekly", requireAuth, requireRole("Admin"), async (_req, res) => {
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  const [completedTrips, revenue] = await Promise.all([
    prisma.trip.count({ where: { status: "COMPLETED", completedAt: { gte: weekAgo } } }),
    prisma.payment.aggregate({
      where: { status: "SUCCEEDED", paidAt: { gte: weekAgo } },
      _sum: { amount: true },
    }),
  ]);

  res.json({
    tripsCompletedThisWeek: completedTrips,
    revenueThisWeek: revenue._sum.amount ?? 0,
  });
});

const meSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
});

// Admin: create/upsert my own admin profile — same "Cognito sign-up has no
// Postgres row yet" bootstrap pattern as /riders/me and /drivers/me.
adminRouter.post("/admin/me", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = meSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const admin = await prisma.user.upsert({
    where: { cognitoSub: req.user!.sub },
    update: {},
    create: { cognitoSub: req.user!.sub, role: "ADMIN", ...parsed.data },
  });
  res.status(201).json(admin);
});

// Admin: get my own profile
adminRouter.get("/admin/me", requireAuth, requireRole("Admin"), async (req, res) => {
  const admin = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!admin) return res.status(404).json({ error: "Admin profile not found" });
  res.json(admin);
});
