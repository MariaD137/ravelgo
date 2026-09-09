import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";
import { MAX_MONEY_AMOUNT, toCents } from "../lib/money";
import { getPaymentSettings, isCashPaymentAllowed } from "../lib/payment-rules";
import { notifyUser } from "../lib/notifications";
import { AlreadyChargedError, chargeWalletForDelivery } from "./wallet";
import { recordDeliveryCommission } from "./ledger";

export type CourierPaymentMethod = "CARD" | "WALLET" | "CASH";

/** The delivery is not in a state where it can be charged. Maps to 409. */
export class DeliveryNotChargeableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DeliveryNotChargeableError";
  }
}

/** A CASH payment was attempted above the configured cash limit (or cash is disabled). Maps to 400. */
export class DeliveryCashLimitExceededError extends Error {
  constructor(public readonly limit: number) {
    super(`Cash payments are limited to ${limit} per delivery. Please select Card or RavelGo Cash.`);
    this.name = "DeliveryCashLimitExceededError";
  }
}

export interface ChargeableCourierRequest {
  id: string;
  senderId: string;
  driverId: string | null;
  deliveryVehicleClass: "BIKE" | "CAR" | "SUV" | "VAN" | null;
  status: string;
  finalFare: number | null;
}

/**
 * Settle a delivery's payment. Mirrors settleTripPayment exactly (same
 * three-method shape, same one-Payment-per-request guarantee via
 * Payment.courierRequestId @unique, same never-trust-the-client amount —
 * always the server-side request.finalFare) so a delivery gets the identical
 * commission/ledger treatment a ride does, not a second, weaker payment path.
 */
export async function settleCourierPayment(
  request: ChargeableCourierRequest,
  method: CourierPaymentMethod,
): Promise<{ payment: unknown; clientSecret?: string | null }> {
  if (request.status !== "DELIVERED" || request.finalFare == null) {
    throw new DeliveryNotChargeableError("Delivery must be DELIVERED with a finalFare before it can be charged");
  }
  if (!Number.isFinite(request.finalFare) || request.finalFare <= 0 || request.finalFare > MAX_MONEY_AMOUNT) {
    throw new DeliveryNotChargeableError("Delivery finalFare is outside the chargeable range");
  }

  const existing = await prisma.payment.findUnique({ where: { courierRequestId: request.id } });
  if (existing) throw new AlreadyChargedError();

  if (method === "CASH") {
    const settings = await getPaymentSettings();
    if (!(await isCashPaymentAllowed(request.finalFare))) {
      throw new DeliveryCashLimitExceededError(settings.cashPaymentLimit);
    }
    const payment = await prisma.payment.create({
      data: {
        courierRequestId: request.id,
        userId: request.senderId,
        amount: request.finalFare,
        method: "CASH",
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    });
    await recordDeliveryCommission(request, payment);
    await notifyUser(
      request.senderId,
      "PAYMENT_SUCCEEDED",
      "Payment successful",
      `Your cash payment of ${request.finalFare} for this delivery was recorded.`,
      { type: "COURIER_REQUEST", id: request.id },
    );
    return { payment };
  }

  if (method === "CARD") {
    const intent = await stripeClient.paymentIntents.create({
      amount: toCents(request.finalFare),
      currency: "usd",
      metadata: { type: "courier_delivery", courierRequestId: request.id },
    });
    const payment = await prisma.payment.create({
      data: {
        courierRequestId: request.id,
        userId: request.senderId,
        amount: request.finalFare,
        method: "CARD",
        status: "PENDING",
        providerReference: intent.id,
      },
    });
    return { payment, clientSecret: intent.client_secret };
  }

  // WALLET: settle immediately.
  const wallet = await prisma.walletAccount.findUnique({ where: { userId: request.senderId } });
  if (!wallet) throw new DeliveryNotChargeableError("Sender has no wallet; top up before paying by wallet");

  const payment = await chargeWalletForDelivery({
    walletId: wallet.id,
    amountCents: toCents(request.finalFare),
    courierRequestId: request.id,
    senderId: request.senderId,
    fareAmount: request.finalFare,
  });
  await recordDeliveryCommission(request, payment);
  await notifyUser(
    request.senderId,
    "PAYMENT_SUCCEEDED",
    "Payment successful",
    `${request.finalFare} was paid from your RavelGo Cash balance for this delivery.`,
    { type: "COURIER_REQUEST", id: request.id },
  );
  return { payment };
}
