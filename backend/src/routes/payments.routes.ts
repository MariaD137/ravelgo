import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { stripeClient } from "../billing/stripe";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { debitWalletForRide, InsufficientFundsError } from "../services/wallet";

export const paymentsRouter = Router();

// Cash is intentionally NOT a payment method: with cash the rider hands money
// straight to the driver, RavelGo never touches it, and the platform can't
// take its commission or remit the driver's share. Every ride is paid by CARD
// (Stripe) or from the rider's Stripe-funded RavelGo WALLET, both of which
// keep the funds under RavelGo's control.
const chargeSchema = z.object({
  method: z.enum(["CARD", "WALLET"]).default("CARD"),
});

// Driver or Admin: charge the rider for a completed trip's final (tax-inclusive)
// fare. CARD creates a real Stripe PaymentIntent and a PENDING Payment whose
// outcome arrives via POST /billing/webhook. WALLET debits the rider's real
// prepaid balance atomically and settles immediately (the funds are already
// held by RavelGo from a prior Stripe top-up).
paymentsRouter.post("/trips/:id/charge", sensitiveLimiter, requireAuth, requireRole("Driver", "Admin"), async (req, res, next) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id }, include: { driver: { include: { user: true } } } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.status !== "COMPLETED" || trip.finalFare == null) {
    return res.status(409).json({ error: "Trip must be COMPLETED with a finalFare before it can be charged" });
  }
  // Defense in depth: finalFare is already bounded when written (trips.routes.ts),
  // but this is the exact value that becomes a real charge, so re-check it here
  // rather than trusting that every write path stayed in range.
  if (!Number.isFinite(trip.finalFare) || trip.finalFare <= 0 || trip.finalFare > MAX_MONEY_AMOUNT) {
    return res.status(409).json({ error: "Trip finalFare is outside the chargeable range" });
  }

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && trip.driver?.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to charge this trip" });
  }

  const existing = await prisma.payment.findUnique({ where: { tripId: trip.id } });
  if (existing) return res.status(409).json({ error: "Trip has already been charged" });

  if (parsed.data.method === "CARD") {
    const intent = await stripeClient.paymentIntents.create({
      amount: toCents(trip.finalFare),
      currency: "usd",
      metadata: { tripId: trip.id },
    });
    const payment = await prisma.payment.create({
      data: {
        tripId: trip.id,
        userId: trip.riderId,
        amount: trip.finalFare,
        method: "CARD",
        status: "PENDING",
        providerReference: intent.id,
      },
    });
    return res.status(201).json({ ...payment, clientSecret: intent.client_secret });
  }

  // WALLET: the rider must have a funded wallet with sufficient balance.
  const wallet = await prisma.walletAccount.findUnique({ where: { userId: trip.riderId } });
  if (!wallet) return res.status(409).json({ error: "Rider has no wallet; top up before paying by wallet" });

  try {
    await debitWalletForRide(wallet.id, toCents(trip.finalFare), trip.id);
  } catch (err) {
    if (err instanceof InsufficientFundsError) {
      return res.status(402).json({ error: "Insufficient wallet balance" });
    }
    return next(err);
  }

  const payment = await prisma.payment.create({
    data: {
      tripId: trip.id,
      userId: trip.riderId,
      amount: trip.finalFare,
      method: "WALLET",
      status: "SUCCEEDED",
      paidAt: new Date(),
    },
  });
  res.status(201).json(payment);
});

// Rider (who owns the payment) or Admin: a receipt for a charged trip
paymentsRouter.get("/payments/:id/receipt", requireAuth, async (req, res) => {
  const payment = await prisma.payment.findUnique({
    where: { id: req.params.id },
    include: { trip: true, user: true },
  });
  if (!payment) return res.status(404).json({ error: "Payment not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && payment.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to view this receipt" });
  }

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
