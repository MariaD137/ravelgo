import { Router } from "express";
import { z } from "zod";
import type { PaymentMethod, PaymentStatus } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { notifyUser } from "../lib/notifications";
import { containsInsensitive, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { paystackClient } from "../billing/paystack";
import { moneyAmountSchema, toCents } from "../lib/money";
import { AlreadyChargedError, InsufficientFundsError } from "../services/wallet";
import { CashLimitExceededError, settleTripPayment, TripNotChargeableError } from "../services/trip-payment";
import {
  DeliveryCashLimitExceededError,
  DeliveryNotChargeableError,
  settleCourierPayment,
} from "../services/courier-payment";
import { reverseCommission } from "../services/ledger";

export const paymentsRouter = Router();

/** Map the settlement service's typed errors to HTTP; rethrow anything else. */
function respondToSettleError(res: import("express").Response, err: unknown, next: import("express").NextFunction) {
  if (err instanceof InsufficientFundsError) return res.status(402).json({ error: "Insufficient wallet balance" });
  if (err instanceof AlreadyChargedError) return res.status(409).json({ error: "This has already been charged" });
  if (err instanceof CashLimitExceededError) return res.status(400).json({ error: err.message });
  if (err instanceof DeliveryCashLimitExceededError) return res.status(400).json({ error: err.message });
  if (err instanceof TripNotChargeableError) return res.status(409).json({ error: err.message });
  if (err instanceof DeliveryNotChargeableError) return res.status(409).json({ error: err.message });
  return next(err);
}

// RavelGo has exactly three payment methods: CASH, CARD and RavelGo CASH
// (WALLET). CARD (Paystack) and WALLET (the rider's prepaid RavelGo balance)
// keep the funds under RavelGo's control end-to-end. CASH changes hands
// directly between rider and driver and is capped at the configured limit
// (default ₦15,000, see lib/payment-rules.ts) so RavelGo's exposure on money
// it never touches stays bounded — settleTripPayment re-checks that cap
// server-side regardless of what the client asserts.
const chargeSchema = z.object({
  method: z.enum(["CARD", "WALLET", "CASH"]).default("CARD"),
});

// Driver or Admin: charge the rider for a completed trip's final (tax-inclusive)
// fare. CARD initializes a real Paystack transaction and a PENDING Payment
// whose outcome arrives via POST /billing/webhook. WALLET debits the rider's
// real prepaid balance atomically and settles immediately (the funds are
// already held by RavelGo from a prior Paystack top-up).
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
    const { payment, authorizationUrl } = await settleTripPayment(trip, parsed.data.method);
    return res.status(201).json(authorizationUrl ? { ...(payment as object), authorizationUrl } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
});

// Rider (who owns the trip): pay for my OWN completed trip (P0 #1). This is the
// rider-initiated payment path — the driver-charge route above is one way a
// trip gets settled, this is the other. Same server-authoritative amount
// (trip.finalFare), same one-Payment-per-trip guarantee, so the two paths can
// never double-charge: whichever settles first wins and the other gets 409.
// CARD returns a Paystack authorizationUrl for the rider to complete in the
// app; WALLET debits the rider's own prepaid balance immediately.
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
    const { payment, authorizationUrl } = await settleTripPayment(trip, parsed.data.method);
    return res.status(201).json(authorizationUrl ? { ...(payment as object), authorizationUrl } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
});

// Driver or Admin: charge the sender for a delivered package's final fare.
// Mirrors POST /trips/:id/charge exactly — see settleCourierPayment.
paymentsRouter.post("/courier-requests/:id/charge", sensitiveLimiter, requireAuth, requireRole("Driver", "Admin"), async (req, res, next) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const request = await prisma.courierRequest.findUnique({
    where: { id: req.params.id },
    include: { driver: { include: { user: true } } },
  });
  if (!request) return res.status(404).json({ error: "Delivery request not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && request.driver?.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to charge this delivery" });
  }

  try {
    const { payment, authorizationUrl } = await settleCourierPayment(request, parsed.data.method);
    return res.status(201).json(authorizationUrl ? { ...(payment as object), authorizationUrl } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
});

// Rider (who owns the delivery request): pay for my OWN delivered package.
paymentsRouter.post("/courier-requests/:id/pay", sensitiveLimiter, requireAuth, async (req, res, next) => {
  const parsed = chargeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const request = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
  if (!request) return res.status(404).json({ error: "Delivery request not found" });
  if (request.senderId !== user.id) {
    return res.status(403).json({ error: "Not authorized to pay for this delivery" });
  }

  try {
    const { payment, authorizationUrl } = await settleCourierPayment(request, parsed.data.method);
    return res.status(201).json(authorizationUrl ? { ...(payment as object), authorizationUrl } : payment);
  } catch (err) {
    return respondToSettleError(res, err, next);
  }
});

const refundSchema = z.object({
  // Omitted = full refund. Partial refunds proportionally reverse the
  // commission/driver-earnings split — see services/ledger.ts#reverseCommission.
  amount: moneyAmountSchema.optional(),
  reason: z.string().min(1).max(500),
});

/**
 * Actually move the money back for a settled Payment, then reverse its
 * commission on the ledger. Shared by the trip and delivery refund routes
 * below — same logic, just parameterized by which Payment/ledger key to use.
 * CARD refunds through Paystack; WALLET credits the payer's balance directly
 * (RavelGo held those funds); CASH never passed through RavelGo at all, so
 * there is nothing to refund through the platform — only the ledger
 * (commission owed) is reversed, and the actual cash return between rider
 * and driver happens outside the app, same as a cash charge itself does.
 */
async function refundSettledPayment(
  payment: { id: string; amount: number; method: PaymentMethod; providerReference: string | null; userId: string; status: PaymentStatus },
  refundAmount: number,
  ledgerKey: { tripId?: string; courierRequestId?: string },
  reason: string,
): Promise<void> {
  if (payment.method === "CARD" && payment.providerReference) {
    await paystackClient.refundTransaction({ reference: payment.providerReference, amountKobo: toCents(refundAmount) });
  } else if (payment.method === "WALLET") {
    const wallet = await prisma.walletAccount.findUnique({ where: { userId: payment.userId } });
    if (wallet) {
      await prisma.$transaction([
        prisma.walletAccount.update({ where: { id: wallet.id }, data: { balanceCents: { increment: toCents(refundAmount) } } }),
        prisma.walletTransaction.create({
          data: {
            walletId: wallet.id,
            type: "REFUND",
            status: "COMPLETED",
            amountCents: toCents(refundAmount),
            tripId: ledgerKey.tripId,
            courierRequestId: ledgerKey.courierRequestId,
          },
        }),
      ]);
    }
  }
  // CASH: nothing moves through RavelGo — see doc comment above.

  const isFull = refundAmount >= payment.amount - 0.005;
  await prisma.payment.update({ where: { id: payment.id }, data: { status: isFull ? "REFUNDED" : payment.status } });
  await reverseCommission({ ...ledgerKey, refundAmount, reason });
}

// Admin: refund a trip's payment (full or partial). Reverses the commission
// on the ledger and, for CARD/WALLET, actually returns the funds.
paymentsRouter.post("/trips/:id/refund", sensitiveLimiter, requireAuth, requireAdminPermission("payouts:write"), async (req, res) => {
  const parsed = refundSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const payment = await prisma.payment.findUnique({ where: { tripId: trip.id } });
  if (!payment || payment.status !== "SUCCEEDED") {
    return res.status(409).json({ error: "This trip has no successful payment to refund" });
  }
  const refundAmount = parsed.data.amount ?? payment.amount;
  if (refundAmount > payment.amount) {
    return res.status(400).json({ error: "Refund amount cannot exceed the original payment" });
  }

  await refundSettledPayment(payment, refundAmount, { tripId: trip.id }, parsed.data.reason);
  await recordAudit({
    actorSub: req.user!.sub,
    action: "TRIP_PAYMENT_REFUNDED",
    entityType: "Trip",
    entityId: trip.id,
    metadata: { refundAmount, reason: parsed.data.reason },
  });
  await notifyUser(trip.riderId, "PAYMENT_SUCCEEDED", "Refund issued", `${refundAmount} was refunded for this ride.`, {
    type: "TRIP",
    id: trip.id,
  });
  res.json({ refunded: refundAmount });
});

// Admin: refund a delivery's payment. Mirrors the trip refund route exactly.
paymentsRouter.post("/courier-requests/:id/refund", sensitiveLimiter, requireAuth, requireAdminPermission("payouts:write"), async (req, res) => {
  const parsed = refundSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const request = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
  if (!request) return res.status(404).json({ error: "Delivery request not found" });

  const payment = await prisma.payment.findUnique({ where: { courierRequestId: request.id } });
  if (!payment || payment.status !== "SUCCEEDED") {
    return res.status(409).json({ error: "This delivery has no successful payment to refund" });
  }
  const refundAmount = parsed.data.amount ?? payment.amount;
  if (refundAmount > payment.amount) {
    return res.status(400).json({ error: "Refund amount cannot exceed the original payment" });
  }

  await refundSettledPayment(payment, refundAmount, { courierRequestId: request.id }, parsed.data.reason);
  await recordAudit({
    actorSub: req.user!.sub,
    action: "DELIVERY_PAYMENT_REFUNDED",
    entityType: "CourierRequest",
    entityId: request.id,
    metadata: { refundAmount, reason: parsed.data.reason },
  });
  await notifyUser(request.senderId, "PAYMENT_SUCCEEDED", "Refund issued", `${refundAmount} was refunded for this delivery.`, {
    type: "COURIER_REQUEST",
    id: request.id,
  });
  res.json({ refunded: refundAmount });
});

// Rider (who owns the payment) or Admin: a receipt for a charged trip or delivery.
paymentsRouter.get("/payments/:id/receipt", requireAuth, async (req, res) => {
  const payment = await prisma.payment.findUnique({
    where: { id: req.params.id },
    include: { trip: true, courierRequest: true, user: true },
  });
  if (!payment) return res.status(404).json({ error: "Payment not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin && payment.user.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to view this receipt" });
  }

  const pickup = payment.trip?.pickup ?? payment.courierRequest?.pickupAddress ?? null;
  const destination = payment.trip?.destination ?? payment.courierRequest?.dropoffAddress ?? null;

  res.json({
    paymentId: payment.id,
    tripId: payment.tripId,
    courierRequestId: payment.courierRequestId,
    pickup,
    destination,
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

// Admin: view all payments, optionally narrowed by a ?q= search against the
// transaction reference or the paying user's name/email.
paymentsRouter.get("/payments", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = paginationQuerySchema.merge(searchQuerySchema).safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, q } = parsed.data;
  const where: Prisma.PaymentWhereInput = q
    ? {
        OR: [
          { providerReference: containsInsensitive(q) },
          { id: containsInsensitive(q) },
          { user: { firstName: containsInsensitive(q) } },
          { user: { lastName: containsInsensitive(q) } },
          { user: { email: containsInsensitive(q) } },
        ],
      }
    : {};

  const [payments, total, byMethod] = await Promise.all([
    prisma.payment.findMany({
      where,
      include: { user: true, trip: true },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.payment.count({ where }),
    // All-time SUCCEEDED revenue per method, computed here over the whole
    // table. The Admin App's Payments overview used to sum whichever rows
    // fell in its single 100-row fetch, which silently under-reported the
    // moment there were more payments than that.
    prisma.payment.groupBy({ by: ["method"], where: { status: "SUCCEEDED" }, _sum: { amount: true } }),
  ]);
  const totals = { cash: 0, card: 0, wallet: 0 };
  for (const row of byMethod) {
    const sum = row._sum.amount ?? 0;
    if (row.method === "CASH") totals.cash = sum;
    else if (row.method === "CARD") totals.card = sum;
    else if (row.method === "WALLET") totals.wallet = sum;
  }
  res.json({ ...paginate(payments, total, page, pageSize), totals });
});
