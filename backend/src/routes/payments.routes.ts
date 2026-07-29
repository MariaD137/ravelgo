import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const paymentsRouter = Router();

const chargeSchema = z.object({
  method: z.enum(["CARD", "CASH", "WALLET"]).default("CARD"),
});

// Driver or Admin: charge the rider for a completed trip's final fare.
// This is a bookkeeping record, not a live processor integration (PAY-01/02
// wire a real processor in later) — it exists so a trip has exactly one
// payment record to reconcile against.
paymentsRouter.post("/trips/:id/charge", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id }, include: { driver: { include: { user: true } } } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.status !== "COMPLETED" || trip.finalFare == null) {
    return res.status(409).json({ error: "Trip must be COMPLETED with a finalFare before it can be charged" });
  }

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && trip.driver?.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to charge this trip" });
  }

  const existing = await prisma.payment.findUnique({ where: { tripId: trip.id } });
  if (existing) return res.status(409).json({ error: "Trip has already been charged" });

  const payment = await prisma.payment.create({
    data: {
      tripId: trip.id,
      userId: trip.riderId,
      amount: trip.finalFare,
      method: parsed.data.method,
      status: "SUCCEEDED",
      paidAt: new Date(),
    },
  });
  res.status(201).json(payment);
});

// Rider: view my own payment history
paymentsRouter.get("/payments/mine", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const payments = await prisma.payment.findMany({
    where: { userId: user.id },
    include: { trip: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(payments);
});

// Admin: view all payments
paymentsRouter.get("/payments", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [payments, total] = await Promise.all([
    prisma.payment.findMany({
      include: { user: true, trip: true },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.payment.count(),
  ]);
  res.json(paginate(payments, total, page, pageSize));
});
