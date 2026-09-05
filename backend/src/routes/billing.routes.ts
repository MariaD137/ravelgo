import { Router } from "express";
import type Stripe from "stripe";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { logSecurityEvent } from "../lib/security-log";
import { creditWalletFromTopup, failWalletTopup } from "../services/wallet";

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
    const succeeded = event.type === "payment_intent.succeeded";

    // Three kinds of PaymentIntent flow through here, told apart by metadata
    // set when each was created: a wallet top-up (wallet.routes.ts) credits
    // the rider's balance on success; a rental booking card payment
    // (rental-payment.ts) confirms that booking; anything else is a trip card
    // charge (payments.routes.ts) that settles that trip's Payment row.
    if (intent.metadata?.type === "wallet_topup") {
      if (succeeded) {
        await creditWalletFromTopup(intent.id);
      } else {
        await failWalletTopup(intent.id);
      }
    } else if (intent.metadata?.type === "rental_booking") {
      const booking = await prisma.rentalBooking.findFirst({ where: { providerReference: intent.id } });
      if (booking) {
        await prisma.rentalBooking.update({
          where: { id: booking.id },
          data: {
            status: succeeded ? "CONFIRMED" : booking.status,
            paymentStatus: succeeded ? "SUCCEEDED" : "FAILED",
          },
        });
      }
    } else {
      const payment = await prisma.payment.findFirst({ where: { providerReference: intent.id } });
      if (payment) {
        await prisma.payment.update({
          where: { id: payment.id },
          data: {
            status: succeeded ? "SUCCEEDED" : "FAILED",
            paidAt: succeeded ? new Date() : undefined,
          },
        });
      }
    }

    if (!succeeded) {
      // A spike in these is worth alerting on (see monitoring-stack.ts) — it
      // can signal card-testing abuse against the platform.
      logSecurityEvent("PAYMENT_FAILURE", req, { intent: intent.id });
    }
  }

  res.json({ received: true });
});
