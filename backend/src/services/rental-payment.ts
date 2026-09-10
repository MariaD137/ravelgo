import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
import { notifyUser } from "../lib/notifications";
import { InsufficientFundsError } from "./wallet";

export type RentalPaymentMethod = "CARD" | "WALLET";

/** The booking is not in a state where it can be paid for (already paid, cancelled, or a bad amount). Maps to 409. */
export class RentalBookingNotChargeableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RentalBookingNotChargeableError";
  }
}

/** Just the booking fields the settlement logic needs. */
export interface ChargeableRentalBooking {
  id: string;
  renterId: string;
  status: string;
  paymentStatus: string;
  totalPrice: number;
}

/**
 * Settle a rental booking's payment. Mirrors settleTripPayment: the amount
 * charged is always the server-side booking.totalPrice — never a value from
 * the client. CARD creates a real Stripe PaymentIntent and leaves the booking
 * PENDING_PAYMENT until the signed webhook confirms it; WALLET debits the
 * renter's real balance atomically and confirms immediately.
 */
export async function chargeRentalBooking(
  booking: ChargeableRentalBooking,
  method: RentalPaymentMethod,
): Promise<{ booking: unknown; clientSecret?: string | null }> {
  if (booking.status !== "PENDING_PAYMENT" || booking.paymentStatus === "SUCCEEDED") {
    throw new RentalBookingNotChargeableError("This booking has already been paid for or is no longer payable");
  }
  // Defense in depth: totalPrice is bounded when written, but it becomes a
  // real charge here, so re-check rather than trusting every write path stayed in range.
  if (!Number.isFinite(booking.totalPrice) || booking.totalPrice <= 0 || booking.totalPrice > MAX_MONEY_AMOUNT) {
    throw new RentalBookingNotChargeableError("Booking total is outside the chargeable range");
  }

  if (method === "CARD") {
    const intent = await stripeClient.paymentIntents.create({
      amount: toCents(booking.totalPrice),
      currency: "usd",
      metadata: { type: "rental_booking", rentalBookingId: booking.id },
    });
    const updated = await prisma.rentalBooking.update({
      where: { id: booking.id },
      data: { paymentMethod: "CARD", paymentStatus: "PENDING", providerReference: intent.id },
    });
    return { booking: updated, clientSecret: intent.client_secret };
  }

  // WALLET: settle immediately from the renter's real prepaid balance, in one
  // transaction so the debit + ledger + booking update can never diverge.
  const wallet = await prisma.walletAccount.findUnique({ where: { userId: booking.renterId } });
  if (!wallet) throw new RentalBookingNotChargeableError("You have no wallet; top up before paying by wallet");

  const amountCents = toCents(booking.totalPrice);
  const updated = await prisma.$transaction(async (tx) => {
    const fresh = await tx.rentalBooking.findUnique({ where: { id: booking.id } });
    if (!fresh || fresh.status !== "PENDING_PAYMENT" || fresh.paymentStatus === "SUCCEEDED") {
      throw new RentalBookingNotChargeableError("This booking has already been paid for or is no longer payable");
    }

    const debited = await tx.walletAccount.updateMany({
      where: { id: wallet.id, balanceCents: { gte: amountCents } },
      data: { balanceCents: { decrement: amountCents } },
    });
    if (debited.count === 0) throw new InsufficientFundsError();

    await tx.walletTransaction.create({
      data: {
        walletId: wallet.id,
        type: "RENTAL_PAYMENT",
        status: "COMPLETED",
        amountCents: -amountCents,
        rentalBookingId: booking.id,
      },
    });

    return tx.rentalBooking.update({
      where: { id: booking.id },
      data: { status: "CONFIRMED", paymentMethod: "WALLET", paymentStatus: "SUCCEEDED" },
    });
  });

  await notifyUser(
    booking.renterId,
    "RENTAL_CONFIRMED",
    "Rental confirmed",
    "Your RavelGo Cash payment went through and your rental booking is confirmed.",
    { type: "RENTAL_BOOKING", id: booking.id },
  );
  return { booking: updated };
}

/**
 * Cancel a booking. If it was already paid, refund it: a CARD payment is
 * refunded through Stripe, a WALLET payment is credited straight back to the
 * renter's balance — both leave an auditable trail, never a silent write-off.
 */
export async function cancelRentalBooking(booking: ChargeableRentalBooking & { paymentMethod: string | null; providerReference: string | null }) {
  if (booking.status === "CANCELLED" || booking.status === "COMPLETED") {
    throw new RentalBookingNotChargeableError(`Booking is already ${booking.status.toLowerCase()}`);
  }

  if (booking.paymentStatus === "SUCCEEDED") {
    if (booking.paymentMethod === "CARD" && booking.providerReference) {
      await stripeClient.refunds.create({ payment_intent: booking.providerReference });
    } else if (booking.paymentMethod === "WALLET") {
      const wallet = await prisma.walletAccount.findUnique({ where: { userId: booking.renterId } });
      if (wallet) {
        await prisma.$transaction([
          prisma.walletAccount.update({ where: { id: wallet.id }, data: { balanceCents: { increment: toCents(booking.totalPrice) } } }),
          prisma.walletTransaction.create({
            data: {
              walletId: wallet.id,
              type: "REFUND",
              status: "COMPLETED",
              amountCents: toCents(booking.totalPrice),
              rentalBookingId: booking.id,
            },
          }),
        ]);
      }
    }
    const cancelled = await prisma.rentalBooking.update({
      where: { id: booking.id },
      data: { status: "CANCELLED", paymentStatus: "REFUNDED" },
    });
    await notifyUser(
      booking.renterId,
      "RENTAL_CANCELLED",
      "Rental cancelled",
      "Your rental booking was cancelled and your payment was refunded.",
      { type: "RENTAL_BOOKING", id: booking.id },
    );
    return cancelled;
  }

  const cancelled = await prisma.rentalBooking.update({ where: { id: booking.id }, data: { status: "CANCELLED" } });
  await notifyUser(
    booking.renterId,
    "RENTAL_CANCELLED",
    "Rental cancelled",
    "Your rental booking was cancelled.",
    { type: "RENTAL_BOOKING", id: booking.id },
  );
  return cancelled;
}

/**
 * Close out CONFIRMED bookings whose date range has genuinely ended
 * (endDate has passed) — nothing else about them is checked or assumed;
 * a booking that is still within its dates, or not CONFIRMED (PENDING_
 * PAYMENT, CANCELLED, already COMPLETED), is never touched.
 *
 * Safe to call as often and from as many places as convenient:
 *  - Idempotent: a booking already COMPLETED is not matched by the WHERE
 *    clause again, so re-running this is always a no-op for it.
 *  - Multi-instance safe: each booking is closed via its own atomic
 *    conditional `updateMany` (status: "CONFIRMED" re-checked in the WHERE),
 *    so if two instances race on the same booking, only the one whose
 *    UPDATE actually matches a row (count === 1) treats it as newly
 *    completed and notifies; the loser's updateMany matches 0 rows and is a
 *    silent no-op — mirrors the exact pattern services/matching.ts's
 *    expireStaleOffers() already uses for the same class of problem.
 *  - Timezone-agnostic: endDate is stored as an absolute UTC instant, and
 *    it's compared against the current instant (`new Date()`) — there is no
 *    local calendar-day ambiguity to get wrong.
 *
 * Called both periodically (see index.ts's startRentalBookingSweep) and
 * opportunistically wherever a renter/driver's bookings are read
 * (rentals.routes.ts), so nobody has to wait for the periodic sweep to see
 * an accurate status.
 */
export async function reconcileExpiredRentalBookings(): Promise<number> {
  const due = await prisma.rentalBooking.findMany({
    where: { status: "CONFIRMED", endDate: { lte: new Date() } },
    select: { id: true, renterId: true },
  });

  let completed = 0;
  for (const { id, renterId } of due) {
    const { count } = await prisma.rentalBooking.updateMany({
      where: { id, status: "CONFIRMED", endDate: { lte: new Date() } },
      data: { status: "COMPLETED" },
    });
    if (count === 0) continue; // already completed by a concurrent reconciliation
    completed += 1;
    await notifyUser(
      renterId,
      "RENTAL_COMPLETED",
      "Rental completed",
      "Your rental period has ended. We hope you enjoyed the ride!",
      { type: "RENTAL_BOOKING", id },
    );
  }
  return completed;
}

// Rental completion isn't time-critical the way a ride offer's 20s window is
// — a booking that ended an hour ago being marked COMPLETED an hour late has
// no real consequence — so this runs far less often than
// matching.ts's startOfferExpirySweep, purely as a backstop for a booking
// nobody happens to read via the opportunistic call sites in
// rentals.routes.ts.
const RENTAL_SWEEP_INTERVAL_MS = 15 * 60_000;

export function startRentalBookingSweep(intervalMs = RENTAL_SWEEP_INTERVAL_MS): ReturnType<typeof setInterval> {
  return setInterval(() => {
    reconcileExpiredRentalBookings().catch((err) => console.error("Failed to reconcile expired rental bookings", err));
  }, intervalMs);
}
