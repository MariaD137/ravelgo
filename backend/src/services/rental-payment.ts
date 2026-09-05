import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
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
    return prisma.rentalBooking.update({
      where: { id: booking.id },
      data: { status: "CANCELLED", paymentStatus: "REFUNDED" },
    });
  }

  return prisma.rentalBooking.update({ where: { id: booking.id }, data: { status: "CANCELLED" } });
}
