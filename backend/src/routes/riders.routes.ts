import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

export const ridersRouter = Router();

// Admin: list all riders
ridersRouter.get("/riders", requireAuth, requireRole("Admin"), async (_req, res) => {
  const riders = await prisma.user.findMany({
    where: { role: "RIDER" },
    orderBy: { createdAt: "desc" },
  });
  res.json(riders);
});

// Admin: get a single rider with trip history
ridersRouter.get("/riders/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const rider = await prisma.user.findFirst({
    where: { id: req.params.id, role: "RIDER" },
    include: { ridesAsRider: { orderBy: { requestedAt: "desc" }, take: 20 } },
  });
  if (!rider) return res.status(404).json({ error: "Rider not found" });
  res.json(rider);
});

const statusSchema = z.object({ suspended: z.boolean() });

// Admin: suspend / reactivate a rider
ridersRouter.patch("/riders/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rider = await prisma.user.update({
    where: { id: req.params.id },
    data: { suspended: parsed.data.suspended },
  });
  res.json(rider);
});

// Rider: get my own profile (creates it on first call, since Cognito sign-up
// doesn't itself create a Postgres row — the app calls this right after auth)
const meSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phoneNumber: z.string().optional(),
});

ridersRouter.post("/riders/me", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = meSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rider = await prisma.user.upsert({
    where: { cognitoSub: req.user!.sub },
    update: {},
    create: { cognitoSub: req.user!.sub, role: "RIDER", ...parsed.data },
  });
  res.status(201).json(rider);
});

ridersRouter.get("/riders/me", requireAuth, requireRole("Rider"), async (req, res) => {
  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider profile not found" });
  res.json(rider);
});
