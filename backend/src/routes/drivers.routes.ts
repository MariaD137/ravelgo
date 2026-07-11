import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

export const driversRouter = Router();

// Admin: list all drivers
driversRouter.get("/drivers", requireAuth, requireRole("Admin"), async (_req, res) => {
  const drivers = await prisma.driver.findMany({
    include: { user: true, vehicles: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(drivers);
});

// Admin: get a single driver with documents
driversRouter.get("/drivers/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const driver = await prisma.driver.findUnique({
    where: { id: req.params.id },
    include: { user: true, vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver not found" });
  res.json(driver);
});

const statusSchema = z.object({
  status: z.enum(["ACTIVE", "PENDING_REVIEW", "SUSPENDED"]),
});

// Admin: suspend / reactivate a driver
driversRouter.patch("/drivers/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  res.json(driver);
});

// Driver: get my own profile
driversRouter.get("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  res.json(driver);
});

// Driver: toggle online preference is handled client-side / via a lightweight presence
// table in a later iteration; ride matching (websocket/App Sync) is intentionally out
// of scope for this MVP skeleton.
