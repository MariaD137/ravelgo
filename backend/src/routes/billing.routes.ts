import { Router } from "express";
import type Stripe from "stripe";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { logSecurityEvent } from "../lib/security-log";
import { notifyAllAdmins, notifyUser } from "../lib/notifications";
import { creditWalletFromTopup, failWalletTopup } from "../services/wallet";
import { recordDeliveryCommission, recordRideCommission } from "../services/ledger";

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
    } else if (intent.metadata?.type === "courier_delivery") {
      const payment = await prisma.payment.findFirst({ where: { providerReference: intent.id } });
      if (payment && payment.courierRequestId) {
        await prisma.payment.update({
          where: { id: payment.id },
          data: { status: succeeded ? "SUCCEEDED" : "FAILED", paidAt: succeeded ? new Date() : undefined },
        });
        if (succeeded) {
          const request = await prisma.courierRequest.findUnique({ where: { id: payment.courierRequestId } });
          if (request) await recordDeliveryCommission(request, payment);
        }
        await notifyUser(
          payment.userId,
          succeeded ? "PAYMENT_SUCCEEDED" : "PAYMENT_FAILED",
          succeeded ? "Payment successful" : "Payment failed",
          succeeded
            ? `Your card payment of ${payment.amount} for this delivery went through.`
            : `Your card payment of ${payment.amount} for this delivery could not be completed.`,
          { type: "COURIER_REQUEST", id: payment.courierRequestId },
        );
        if (!succeeded) {
          await notifyAllAdmins(
            "ADMIN_PAYMENT_FAILED",
            "Delivery payment failed",
            `A card payment of ${payment.amount} for delivery ${payment.courierRequestId} failed.`,
            { type: "COURIER_REQUEST", id: payment.courierRequestId },
          );
        }
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
        await notifyUser(
          booking.renterId,
          succeeded ? "RENTAL_CONFIRMED" : "PAYMENT_FAILED",
          succeeded ? "Rental confirmed" : "Payment failed",
          succeeded
            ? "Your card payment went through and your rental booking is confirmed."
            : "Your card payment for this rental booking could not be completed.",
          { type: "RENTAL_BOOKING", id: booking.id },
        );
        if (!succeeded) {
          await notifyAllAdmins(
            "ADMIN_PAYMENT_FAILED",
            "Rental payment failed",
            `A card payment for rental booking ${booking.id} failed.`,
            { type: "RENTAL_BOOKING", id: booking.id },
          );
        }
      }
    } else {
      // Every other PaymentIntent that reaches this webhook is a trip card
      // charge (payments.routes.ts) — the wallet_topup/rental_booking/
      // courier_delivery branches above claim their own metadata.type first.
      const payment = await prisma.payment.findFirst({ where: { providerReference: intent.id } });
      if (payment && payment.tripId) {
        await prisma.payment.update({
          where: { id: payment.id },
          data: {
            status: succeeded ? "SUCCEEDED" : "FAILED",
            paidAt: succeeded ? new Date() : undefined,
          },
        });
        if (succeeded) {
          const trip = await prisma.trip.findUnique({ where: { id: payment.tripId } });
          if (trip) await recordRideCommission(trip, payment, trip.finalFare ?? payment.amount);
        }
        await notifyUser(
          payment.userId,
          succeeded ? "PAYMENT_SUCCEEDED" : "PAYMENT_FAILED",
          succeeded ? "Payment successful" : "Payment failed",
          succeeded
            ? `Your card payment of ${payment.amount} for this ride went through.`
            : `Your card payment of ${payment.amount} for this ride could not be completed.`,
          { type: "TRIP", id: payment.tripId },
        );
        if (!succeeded) {
          await notifyAllAdmins(
            "ADMIN_PAYMENT_FAILED",
            "Ride payment failed",
            `A card payment of ${payment.amount} for trip ${payment.tripId} failed.`,
            { type: "TRIP", id: payment.tripId },
          );
        }
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
