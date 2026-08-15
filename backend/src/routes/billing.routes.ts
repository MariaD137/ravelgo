import { Router } from "express";
import type Stripe from "stripe";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { asyncHandler } from "../middleware/async-handler";

export const billingRouter = Router();

// Stripe webhook: verifies the signature against the exact raw request
// bytes. Mounted in app.ts with express.raw() BEFORE the global
// express.json() — parsing the body as JSON first would consume the
// stream and change its bytes, breaking every real signature check (the
// same gotcha Nettle's billing route hit).
// Mounted at the exact path "/api/billing/webhook" in app.ts (not under a
// shared "/api" prefix router like the other routes) — see the comment
// there for why the raw-body middleware must be scoped this narrowly.
billingRouter.post("/", asyncHandler(async (req, res) => {
  const signature = req.headers["stripe-signature"];
  if (typeof signature !== "string") {
    return res.status(400).json({ error: "Missing stripe-signature header" });
  }
  if (!env.STRIPE_WEBHOOK_SECRET) {
    return res.status(500).json({ error: "STRIPE_WEBHOOK_SECRET is not configured" });
  }

  let event: Stripe.Event;
  try {
    event = stripeClient.webhooks.constructEvent(req.body as Buffer, signature, env.STRIPE_WEBHOOK_SECRET);
  } catch {
    return res.status(400).json({ error: "Invalid webhook signature" });
  }

  if (event.type === "payment_intent.succeeded" || event.type === "payment_intent.payment_failed") {
    const intent = event.data.object as Stripe.PaymentIntent;
    const payment = await prisma.payment.findFirst({ where: { providerReference: intent.id } });
    if (payment) {
      const targetStatus = event.type === "payment_intent.succeeded" ? "SUCCEEDED" : "FAILED";
      // Idempotency guard: skip if the payment already has the target status
      if (payment.status === targetStatus) {
        return res.json({ received: true });
      }
      await prisma.payment.update({
        where: { id: payment.id },
        data: {
          status: targetStatus,
          paidAt: event.type === "payment_intent.succeeded" ? new Date() : undefined,
        },
      });
    }
  } else if (event.type === "charge.refunded") {
    const charge = event.data.object as Stripe.Charge;
    if (charge.payment_intent) {
      const intentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent.id;
      await prisma.payment.updateMany({
        where: { providerReference: intentId },
        data: { status: "REFUNDED" },
      });
    }
  } else if (event.type === "charge.dispute.created") {
    const dispute = event.data.object as Stripe.Dispute;
    if (dispute.payment_intent) {
      const intentId = typeof dispute.payment_intent === "string" ? dispute.payment_intent : dispute.payment_intent.id;
      await prisma.payment.updateMany({
        where: { providerReference: intentId },
        data: { status: "DISPUTED" },
      });
    }
  }

  res.json({ received: true });
}));
