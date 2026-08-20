import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { stripeClient } from "../billing/stripe";
import { withBypass, withUserContext } from "../lib/rls";

export const paymentsRouter = Router();

const chargeSchema = z.object({
  method: z.enum(["CARD", "CASH", "WALLET"]).default("CARD"),
});

// Driver or Admin: charge the rider for a completed trip's final fare.
// Creates a real Stripe PaymentIntent and a Payment row in PENDING —
// PAY-01/02's actual outcome (succeeded/failed) arrives asynchronously via
// POST /billing/webhook once the client confirms the PaymentIntent
// (confirming it is a client-side/mobile-SDK step, out of scope for this
// backend route). CASH/WALLET charges skip Stripe entirely and settle
// immediately, since there's no card to authorize.
paymentsRouter.post("/trips/:id/charge", requireAuth, requireRole("Driver", "Admin"), asyncHandler(async (req, res) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id }, include: { driver: { include: { user: true } } } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.status !== "COMPLETED" || trip.finalFare == null) {
    return res.status(409).json({ error: "Trip must be COMPLETED with a finalFare before it can be charged" });
  }
  const finalFare = trip.finalFare; // narrow once here — the closures below don't retain the guard's narrowing of trip.finalFare

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && trip.driver?.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to charge this trip" });
  }

  // The caller here is the driver or an Admin, not the rider who owns the
  // resulting Payment row (payment.userId = trip.riderId) — so this can't
  // be scoped with the caller's own identity; bypass is correct once the
  // ownership/role check above has already passed.
  const existing = await withBypass((tx) => tx.payment.findUnique({ where: { tripId: trip.id } }));
  if (existing) return res.status(409).json({ error: "Trip has already been charged" });

  if (parsed.data.method === "CARD") {
    const intent = await stripeClient.paymentIntents.create({
      amount: Math.round(finalFare * 100),
      currency: "usd",
      metadata: { tripId: trip.id },
    });
    const payment = await withBypass((tx) =>
      tx.payment.create({
        data: {
          tripId: trip.id,
          userId: trip.riderId,
          amount: finalFare,
          method: "CARD",
          status: "PENDING",
          providerReference: intent.id,
        },
      }),
    );
    return res.status(201).json({ ...payment, clientSecret: intent.client_secret });
  }

  const payment = await withBypass((tx) =>
    tx.payment.create({
      data: {
        tripId: trip.id,
        userId: trip.riderId,
        amount: finalFare,
        method: parsed.data.method,
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    }),
  );
  res.status(201).json(payment);
}));

// Rider (who owns the payment) or Admin: a receipt for a charged trip
paymentsRouter.get("/payments/:id/receipt", requireAuth, asyncHandler(async (req, res) => {
  const isAdmin = req.user!.groups.includes("Admin");

  let payment;
  if (isAdmin) {
    payment = await withBypass((tx) =>
      tx.payment.findUnique({ where: { id: req.params.id }, include: { trip: true, user: true } }),
    );
  } else {
    const caller = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
    if (!caller) return res.status(404).json({ error: "Payment not found" });
    payment = await withUserContext(caller.id, (tx) =>
      tx.payment.findUnique({ where: { id: req.params.id }, include: { trip: true, user: true } }),
    );
  }
  // For a non-Admin caller, RLS already scopes the query above to rows
  // they own, so "exists but belongs to someone else" and "doesn't exist"
  // are indistinguishable here by design — this returns 404 for both
  // instead of leaking existence via a 403.
  if (!payment) return res.status(404).json({ error: "Payment not found" });

  res.json({
    paymentId: payment.id,
    tripId: payment.tripId,
    pickup: payment.trip.pickup,
    destination: payment.trip.destination,
    amount: payment.amount,
    currency: payment.currency,
    method: payment.method,
    status: payment.status,
    paidAt: payment.paidAt,
    issuedAt: payment.createdAt,
  });
}));

// Rider: view my own payment history
paymentsRouter.get("/payments/mine", requireAuth, asyncHandler(async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const where = { userId: user.id };
  const [payments, total] = await withUserContext(user.id, (tx) =>
    Promise.all([
      tx.payment.findMany({
        where,
        include: { trip: true },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      tx.payment.count({ where }),
    ]),
  );
  res.json(paginate(payments, total, page, pageSize));
}));

// Admin: view all payments
paymentsRouter.get("/payments", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [payments, total] = await withBypass((tx) =>
    Promise.all([
      tx.payment.findMany({
        include: { user: true, trip: true },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      tx.payment.count(),
    ]),
  );
  res.json(paginate(payments, total, page, pageSize));
}));
