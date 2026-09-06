import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { AlreadyChargedError, InsufficientFundsError } from "../services/wallet";
import { CashLimitExceededError, settleTripPayment, TripNotChargeableError } from "../services/trip-payment";

export const paymentsRouter = Router();

/** Map the settlement service's typed errors to HTTP; rethrow anything else. */
function respondToSettleError(res: import("express").Response, err: unknown, next: import("express").NextFunction) {
  if (err instanceof InsufficientFundsError) return res.status(402).json({ error: "Insufficient wallet balance" });
  if (err instanceof AlreadyChargedError) return res.status(409).json({ error: "Trip has already been charged" });
  if (err instanceof CashLimitExceededError) return res.status(400).json({ error: err.message });
  if (err instanceof TripNotChargeableError) return res.status(409).json({ error: err.message });
  return next(err);
}

// RavelGo has exactly three payment methods: CASH, CARD and RavelGo CASH
// (WALLET). CARD (Stripe) and WALLET (the rider's prepaid RavelGo balance)
// keep the funds under RavelGo's control end-to-end. CASH changes hands
// directly between rider and driver and is capped at the configured limit
// (default ₦15,000, see lib/payment-rules.ts) so RavelGo's exposure on money
// it never touches stays bounded — settleTripPayment re-checks that cap
// server-side regardless of what the client asserts.
const chargeSchema = z.object({
  method: z.enum(["CARD", "WALLET", "CASH"]).default("CARD"),
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

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && trip.driver?.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to charge this trip" });
  }

  try {
    const { payment, clientSecret } = await settleTripPayment(trip, parsed.data.method);
    return res.status(201).json(clientSecret ? { ...(payment as object), clientSecret } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
});

// Rider (who owns the trip): pay for my OWN completed trip (P0 #1). This is the
// rider-initiated payment path — the driver-charge route above is one way a
// trip gets settled, this is the other. Same server-authoritative amount
// (trip.finalFare), same one-Payment-per-trip guarantee, so the two paths can
// never double-charge: whichever settles first wins and the other gets 409.
// CARD returns a Stripe clientSecret for the rider to confirm in the app's
// PaymentSheet; WALLET debits the rider's own prepaid balance immediately.
paymentsRouter.post("/trips/:id/pay", sensitiveLimiter, requireAuth, async (req, res, next) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  // Ownership: a rider may only pay for their own trip.
  if (trip.riderId !== user.id) {
    return res.status(403).json({ error: "Not authorized to pay for this trip" });
  }

  try {
    const { payment, clientSecret } = await settleTripPayment(trip, parsed.data.method);
    return res.status(201).json(clientSecret ? { ...(payment as object), clientSecret } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
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
