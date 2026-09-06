import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
import { getPaymentSettings, isCashPaymentAllowed } from "../lib/payment-rules";
import { AlreadyChargedError, chargeWalletForRide } from "./wallet";

export type PaymentMethod = "CARD" | "WALLET" | "CASH";

/** The trip is not in a state where it can be charged (not completed, no/invalid finalFare, no wallet). Maps to 409. */
export class TripNotChargeableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TripNotChargeableError";
  }
}

/** A CASH payment was attempted for a fare above the configured cash limit (or cash is disabled). Maps to 400. */
export class CashLimitExceededError extends Error {
  constructor(public readonly limit: number) {
    super(`Cash payments are limited to ${limit} per trip. Please select Card or RavelGo Cash.`);
    this.name = "CashLimitExceededError";
  }
}

/** Just the trip fields the settlement logic needs — both the driver-charge and rider-pay routes pass this. */
export interface ChargeableTrip {
  id: string;
  riderId: string;
  status: string;
  finalFare: number | null;
}

/**
 * Settle a completed trip's payment. This is the single money path shared by
 * the driver-charge and rider-pay routes so the safety properties are written
 * once, not duplicated: the caller does its own authorization, then hands the
 * trip here.
 *
 * Guarantees (unchanged from the original inline charge):
 *  - only a COMPLETED trip with a finite, in-range finalFare is chargeable
 *  - exactly one Payment per trip (Payment.tripId @unique + a fast-path check),
 *    so a second settle — even a concurrent one — gets AlreadyChargedError
 *  - CARD creates a real Stripe PaymentIntent and a PENDING Payment; the outcome
 *    arrives on the signed webhook. WALLET debits the rider's real balance
 *    atomically via chargeWalletForRide (debit + ledger + Payment in one tx).
 *
 * The amount charged is always the server-side trip.finalFare — never a value
 * from the client.
 */
export async function settleTripPayment(
  trip: ChargeableTrip,
  method: PaymentMethod,
): Promise<{ payment: unknown; clientSecret?: string | null }> {
  if (trip.status !== "COMPLETED" || trip.finalFare == null) {
    throw new TripNotChargeableError("Trip must be COMPLETED with a finalFare before it can be charged");
  }
  // Defense in depth: finalFare is bounded when written, but it becomes a real
  // charge here, so re-check rather than trusting every write path stayed in range.
  if (!Number.isFinite(trip.finalFare) || trip.finalFare <= 0 || trip.finalFare > MAX_MONEY_AMOUNT) {
    throw new TripNotChargeableError("Trip finalFare is outside the chargeable range");
  }

  const existing = await prisma.payment.findUnique({ where: { tripId: trip.id } });
  if (existing) throw new AlreadyChargedError();

  if (method === "CASH") {
    // Defense in depth: the rider app hides Cash above the limit, but the
    // server is the only place this is actually enforced — see
    // lib/payment-rules.ts#isCashPaymentAllowed.
    const settings = await getPaymentSettings();
    if (!(await isCashPaymentAllowed(trip.finalFare))) {
      throw new CashLimitExceededError(settings.cashPaymentLimit);
    }
    // Cash changes hands directly between rider and driver — RavelGo never
    // holds it, so unlike CARD/WALLET this settles immediately as SUCCEEDED
    // with no provider round trip. It still becomes a real, owed-to-RavelGo
    // amount from this instant: the driver's cash reconciliation (see
    // cash.routes.ts) sums exactly these rows as "expected cash".
    const payment = await prisma.payment.create({
      data: {
        tripId: trip.id,
        userId: trip.riderId,
        amount: trip.finalFare,
        method: "CASH",
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    });
    return { payment };
  }

  if (method === "CARD") {
    const intent = await stripeClient.paymentIntents.create({
      amount: toCents(trip.finalFare),
      currency: "usd",
      metadata: { tripId: trip.id },
    });
    const payment = await prisma.payment.create({
      data: {
        tripId: trip.id,
        userId: trip.riderId,
        amount: trip.finalFare,
        method: "CARD",
        status: "PENDING",
        providerReference: intent.id,
      },
    });
    return { payment, clientSecret: intent.client_secret };
  }

  // WALLET: settle immediately from the rider's real prepaid balance.
  const wallet = await prisma.walletAccount.findUnique({ where: { userId: trip.riderId } });
  if (!wallet) throw new TripNotChargeableError("Rider has no wallet; top up before paying by wallet");

  const payment = await chargeWalletForRide({
    walletId: wallet.id,
    amountCents: toCents(trip.finalFare),
    tripId: trip.id,
    riderId: trip.riderId,
    fareAmount: trip.finalFare,
  });
  return { payment };
}
