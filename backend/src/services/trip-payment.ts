import { prisma } from "../db/prisma";
import { paystackClient } from "../billing/paystack";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
import { getPaymentSettings, isCashPaymentAllowed } from "../lib/payment-rules";
import { notifyUser } from "../lib/notifications";
import { AlreadyChargedError, chargeWalletForRide } from "./wallet";
import { recordRideCommission } from "./ledger";

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
  driverId: string | null;
  rideCategoryKey: string | null;
  status: string;
  finalFare: number | null;
  // Locked in earlier in the trip lifecycle (trips.routes.ts) — 100%
  // driver-compensation, bundled into the single charge below but never
  // commissioned (see recordRideCommission's fareAmount parameter).
  waitingCharge?: number | null;
  cancellationFee?: number | null;
}

/** The fare plus any locked-in waiting/cancellation charge — the actual amount charged. */
function chargeableTotal(trip: ChargeableTrip): number {
  return (trip.finalFare ?? 0) + (trip.waitingCharge ?? 0) + (trip.cancellationFee ?? 0);
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
 *  - CARD initializes a real Paystack transaction and a PENDING Payment; the
 *    outcome arrives on the signed webhook (verified against Paystack's own
 *    verify endpoint before being trusted — see billing.routes.ts). WALLET
 *    debits the rider's real balance atomically via chargeWalletForRide
 *    (debit + ledger + Payment in one tx).
 *
 * The amount charged is always the server-side trip.finalFare — never a value
 * from the client.
 */
export async function settleTripPayment(
  trip: ChargeableTrip,
  method: PaymentMethod,
): Promise<{ payment: unknown; authorizationUrl?: string | null }> {
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

  // The rider is charged the fare PLUS any waiting/cancellation charge locked
  // in earlier in the trip (trips.routes.ts) — one combined charge, exactly
  // like a real receipt line-items into a single total. Commission is still
  // computed on the fare alone (recordRideCommission's explicit fareAmount
  // below): waiting/cancellation are 100% driver-compensation.
  const chargeAmount = chargeableTotal(trip);

  if (method === "CASH") {
    // Defense in depth: the rider app hides Cash above the limit, but the
    // server is the only place this is actually enforced — see
    // lib/payment-rules.ts#isCashPaymentAllowed.
    const settings = await getPaymentSettings();
    if (!(await isCashPaymentAllowed(chargeAmount))) {
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
        amount: chargeAmount,
        method: "CASH",
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    });
    // Cash settles immediately — the commission is owed to RavelGo from this
    // instant, same as the CashRemittance reconciliation already assumes.
    await recordRideCommission(trip, payment, trip.finalFare ?? 0);
    await notifyUser(
      trip.riderId,
      "PAYMENT_SUCCEEDED",
      "Payment successful",
      `Your cash payment of ${chargeAmount} for this ride was recorded.`,
      { type: "TRIP", id: trip.id },
    );
    return { payment };
  }

  if (method === "CARD") {
    const rider = await prisma.user.findUnique({ where: { id: trip.riderId }, select: { email: true } });
    if (!rider) throw new TripNotChargeableError("Rider profile not found");

    const reference = `ravelgo_trip_${trip.id}`;
    const { authorizationUrl } = await paystackClient.initializeTransaction({
      email: rider.email,
      amountKobo: toCents(chargeAmount),
      reference,
      metadata: { type: "trip", tripId: trip.id },
    });
    const payment = await prisma.payment.create({
      data: {
        tripId: trip.id,
        userId: trip.riderId,
        amount: chargeAmount,
        method: "CARD",
        status: "PENDING",
        provider: "PAYSTACK",
        providerReference: reference,
      },
    });
    return { payment, authorizationUrl };
  }

  // WALLET: settle immediately from the rider's real prepaid balance.
  const wallet = await prisma.walletAccount.findUnique({ where: { userId: trip.riderId } });
  if (!wallet) throw new TripNotChargeableError("Rider has no wallet; top up before paying by wallet");

  const payment = await chargeWalletForRide({
    walletId: wallet.id,
    amountCents: toCents(chargeAmount),
    tripId: trip.id,
    riderId: trip.riderId,
    fareAmount: chargeAmount,
  });
  // WALLET settles immediately too — RavelGo already holds these funds.
  await recordRideCommission(trip, payment, trip.finalFare ?? 0);
  await notifyUser(
    trip.riderId,
    "PAYMENT_SUCCEEDED",
    "Payment successful",
    `${chargeAmount} was paid from your RavelGo Cash balance for this ride.`,
    { type: "TRIP", id: trip.id },
  );
  return { payment };
}
