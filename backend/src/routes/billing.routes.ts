import { Router } from "express";
import type Stripe from "stripe";
import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";

const PRISMA_UNIQUE_CONSTRAINT_VIOLATION = "P2002";

export const billingRouter = Router();

// Stripe webhook: verifies the signature against the exact raw request
// bytes. Mounted in app.ts with express.raw() BEFORE the global
// express.json() — parsing the body as JSON first would consume the
// stream and change its bytes, breaking every real signature check (the
// same gotcha Nettle's billing route hit).
// Mounted at the exact path "/api/billing/webhook" in app.ts (not under a
// shared "/api" prefix router like the other routes) — see the comment
// there for why the raw-body middleware must be scoped this narrowly.
billingRouter.post("/", async (req, res) => {
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

  // Recording the event id is the idempotency check: a unique-constraint
  // violation means Stripe already delivered (or retried) this exact event,
  // so its side effects below must not run a second time. Stripe treats any
  // 2xx as "delivered" and won't retry, so this still returns 200.
  try {
    await prisma.webhookEvent.create({ data: { id: event.id, type: event.type } });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === PRISMA_UNIQUE_CONSTRAINT_VIOLATION) {
      return res.json({ received: true, duplicate: true });
    }
    throw err;
  }

  if (event.type === "payment_intent.succeeded" || event.type === "payment_intent.payment_failed") {
    const intent = event.data.object as Stripe.PaymentIntent;
    const payment = await prisma.payment.findFirst({ where: { providerReference: intent.id } });
    if (payment) {
      await prisma.payment.update({
        where: { id: payment.id },
        data: {
          status: event.type === "payment_intent.succeeded" ? "SUCCEEDED" : "FAILED",
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
});
