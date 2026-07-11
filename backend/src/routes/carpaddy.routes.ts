import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

export const carPaddyRouter = Router();

const submitSchema = z.object({
  plateNumber: z.string().min(1),
});

// Driver: submit a Car Paddy (vehicle license renewal) request
carPaddyRouter.post("/car-paddy", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = submitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const request = await prisma.carPaddyRequest.create({
    data: { driverId: driver.id, plateNumber: parsed.data.plateNumber },
  });
  res.status(201).json(request);
});

// Admin: list all Car Paddy requests
carPaddyRouter.get("/car-paddy", requireAuth, requireRole("Admin"), async (_req, res) => {
  const requests = await prisma.carPaddyRequest.findMany({
    include: { driver: { include: { user: true } } },
    orderBy: { submittedAt: "desc" },
  });
  res.json(requests);
});

const decisionSchema = z.object({
  status: z.enum(["APPROVED", "REJECTED"]),
});

// Admin: approve/reject a Car Paddy request
carPaddyRouter.patch("/car-paddy/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const request = await prisma.carPaddyRequest.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status, reviewedAt: new Date() },
  });
  res.json(request);
});
