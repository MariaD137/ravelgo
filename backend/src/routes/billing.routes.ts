import { Router } from "express";
import { prisma } from "../db/prisma";
import { paystackClient, verifyWebhookSignature } from "../billing/paystack";
import { logSecurityEvent } from "../lib/security-log";
import { notifyAllAdmins, notifyUser } from "../lib/notifications";
import { creditWalletFromTopup, failWalletTopup } from "../services/wallet";
import { recordDeliveryCommission, recordRideCommission } from "../services/ledger";
import { finalizePayoutFromTransferWebhook } from "../services/payouts";

export const billingRouter = Router();

interface PaystackWebhookEvent {
  event: string;
  data: {
    reference?: string;
    status?: string;
    metadata?: Record<string, unknown> | string | null;
    // Present on transfer.success / transfer.failed instead of `reference`
    // (Paystack echoes back the reference RavelGo supplied when initiating
    // the transfer).
    transfer_code?: string;
    reason?: string;
  };
}

/** Paystack sometimes sends metadata as "" instead of omitting it. */
function readMetadataType(metadata: PaystackWebhookEvent["data"]["metadata"]): string | undefined {
  if (!metadata || typeof metadata !== "object") return undefined;
  const type = (metadata as Record<string, unknown>).type;
  return typeof type === "string" ? type : undefined;
}

// Paystack webhook: verifies the signature against the exact raw request
// bytes. Mounted in app.ts with express.raw() BEFORE the global
// express.json() — parsing the body as JSON first would consume the
// stream and change its bytes, breaking every real signature check (the
// same gotcha Nettle's billing route hit).
// Mounted at the exact path "/api/billing/webhook" in app.ts (not under a
// shared "/api" prefix router like the other routes) — see the comment
// there for why the raw-body middleware must be scoped this narrowly.
billingRouter.post("/", async (req, res) => {
  const signature = req.headers["x-paystack-signature"];
  const rawBody = req.body as Buffer;

  if (typeof signature !== "string" || !verifyWebhookSignature(rawBody, signature)) {
    return res.status(400).json({ error: "Invalid webhook signature" });
  }

  let event: PaystackWebhookEvent;
  try {
    event = JSON.parse(rawBody.toString("utf8")) as PaystackWebhookEvent;
  } catch {
    return res.status(400).json({ error: "Malformed webhook body" });
  }

  if (event.event === "charge.success" || event.event === "charge.failed") {
    const reference = event.data.reference;
    if (!reference) return res.json({ received: true });

    // Trust-but-verify (Paystack's own recommended pattern, and stricter
    // than what the removed Stripe integration did): never fulfil purely off
    // the webhook payload. A signature-valid webhook could still describe a
    // stale or manipulated event, so the real transaction state is always
    // re-read from Paystack's own verify endpoint before anything is
    // credited. If verification itself fails (network error, Paystack
    // outage), the whole handler throws and Paystack retries the delivery
    // later rather than this silently no-op'ing.
    const verified = await paystackClient.verifyTransaction(reference);
    const succeeded = verified.status === "success";
    const type = readMetadataType(verified.metadata);

    // Three kinds of transaction flow through here, told apart by metadata
    // set when each was initialized: a wallet top-up (wallet.routes.ts)
    // credits the rider's balance on success; a rental booking card payment
    // (rental-payment.ts) confirms that booking; a courier delivery charge
    // (courier-payment.ts) settles that delivery's Payment; anything else
    // (metadata.type === "trip", set in trip-payment.ts) settles a trip's
    // Payment. Each branch is idempotent against a duplicate webhook
    // delivery for the same reference — Paystack's own docs describe
    // at-least-once delivery — by only acting when the row is still PENDING
    // (a conditional updateMany whose count says whether THIS call won the
    // race), the same pattern already used elsewhere in this codebase
    // (services/rental-payment.ts#reconcileExpiredRentalBookings,
    // services/matching.ts#expireStaleOffers).
    if (type === "wallet_topup") {
      if (succeeded) {
        await creditWalletFromTopup(reference);
      } else {
        await failWalletTopup(reference);
      }
    } else if (type === "courier_delivery") {
      const payment = await prisma.payment.findFirst({ where: { providerReference: reference } });
      if (payment && payment.courierRequestId) {
        const { count } = await prisma.payment.updateMany({
          where: { id: payment.id, status: "PENDING" },
          data: { status: succeeded ? "SUCCEEDED" : "FAILED", paidAt: succeeded ? new Date() : undefined },
        });
        if (count === 1) {
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
      }
    } else if (type === "rental_booking") {
      const booking = await prisma.rentalBooking.findFirst({ where: { providerReference: reference } });
      if (booking) {
        const { count } = await prisma.rentalBooking.updateMany({
          where: { id: booking.id, paymentStatus: "PENDING" },
          data: {
            status: succeeded ? "CONFIRMED" : booking.status,
            paymentStatus: succeeded ? "SUCCEEDED" : "FAILED",
          },
        });
        if (count === 1) {
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
      }
    } else {
      // metadata.type === "trip" (set in trip-payment.ts) is the only other
      // value this webhook is ever sent for.
      const payment = await prisma.payment.findFirst({ where: { providerReference: reference } });
      if (payment && payment.tripId) {
        const { count } = await prisma.payment.updateMany({
          where: { id: payment.id, status: "PENDING" },
          data: { status: succeeded ? "SUCCEEDED" : "FAILED", paidAt: succeeded ? new Date() : undefined },
        });
        if (count === 1) {
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
    }

    if (!succeeded) {
      // A spike in these is worth alerting on (see monitoring-stack.ts) — it
      // can signal card-testing abuse against the platform.
      logSecurityEvent("PAYMENT_FAILURE", req, { reference });
    }
  } else if (event.event === "transfer.success" || event.event === "transfer.failed") {
    // Driver payout finalization — see services/payouts.ts#processPayout,
    // which initiates the transfer and stores its reference, and
    // #finalizePayoutFromTransferWebhook, which is idempotent the same way
    // (only acts on a payout still PROCESSING) for the same reason as above.
    const reference = event.data.reference;
    if (reference) {
      await finalizePayoutFromTransferWebhook(
        reference,
        event.event === "transfer.success",
        event.event === "transfer.failed" ? (event.data.reason ?? "Transfer failed") : undefined,
      );
    }
  }

  res.json({ received: true });
});
