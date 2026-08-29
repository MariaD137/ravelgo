import { Router } from "express";
import type Stripe from "stripe";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { logSecurityEvent } from "../lib/security-log";

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
    if (event.type === "payment_intent.payment_failed") {
      // A spike in these is worth alerting on (see monitoring-stack.ts) — it
      // can signal card-testing abuse against the platform.
      logSecurityEvent("PAYMENT_FAILURE", req, { intent: intent.id });
    }
  }

  res.json({ received: true });
});
