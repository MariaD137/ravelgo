import { prisma } from "../db/prisma";

/**
 * Credit a wallet for a confirmed Paystack top-up. Called from the signed
 * webhook only, never from a client path. Idempotent: Paystack can deliver
 * the same event more than once (its own docs describe at-least-once
 * delivery), so a top-up already marked COMPLETED is a no-op and the balance
 * is never double-credited.
 *
 * The PENDING -> COMPLETED transition itself is the atomic claim: a plain
 * `findUnique` read followed by an unconditional `update` (the previous
 * implementation) is a TOCTOU race — two concurrent/redelivered webhooks for
 * the same reference can both read status "PENDING" before either commits,
 * and Prisma's `update({where: {id}})` succeeds regardless of the row's
 * current status, so both would go on to credit the balance. Using
 * `updateMany({where: {id, status: "PENDING"}})` instead re-evaluates that
 * status condition against Postgres's current, post-lock row value — a
 * second caller's conditional update then matches zero rows and does
 * nothing. Same conditional-updateMany-then-check-count pattern this
 * webhook handler already uses for every other transaction type (see
 * billing.routes.ts).
 */
export async function creditWalletFromTopup(providerReference: string): Promise<void> {
  const txn = await prisma.walletTransaction.findUnique({ where: { providerReference } });
  if (!txn || txn.type !== "TOPUP") return; // not a top-up this function is responsible for

  await prisma.$transaction(async (tx) => {
    const claim = await tx.walletTransaction.updateMany({
      where: { id: txn.id, status: "PENDING" },
      data: { status: "COMPLETED" },
    });
    if (claim.count !== 1) return; // already credited by a concurrent or earlier delivery
    await tx.walletAccount.update({
      where: { id: txn.walletId },
      data: { balanceCents: { increment: txn.amountCents } },
    });
  });
}

/** Mark a top-up FAILED when Paystack reports the charge failed. Idempotent. */
export async function failWalletTopup(providerReference: string): Promise<void> {
  await prisma.walletTransaction.updateMany({
    where: { providerReference, type: "TOPUP", status: "PENDING" },
    data: { status: "FAILED" },
  });
}

export class InsufficientFundsError extends Error {
  constructor() {
    super("Insufficient wallet balance");
    this.name = "InsufficientFundsError";
  }
}

export class AlreadyChargedError extends Error {
  constructor() {
    super("Trip has already been charged");
    this.name = "AlreadyChargedError";
  }
}

/**
 * Charge a wallet for a completed ride — the balance debit, the ledger entry,
 * and the Payment record are written in ONE transaction (P0 #5).
 *
 * Two failure modes this closes, both of which previously double-debited a
 * rider (the debit committed in its own transaction, and the Payment row was
 * created separately afterwards):
 *
 *  - A crash between the debit and the Payment insert left the balance
 *    decremented with no Payment, so the trip looked uncharged and a retry
 *    debited a second time. Now both live in one transaction: if the Payment
 *    insert fails, the debit rolls back with it.
 *  - Two concurrent charges both passed a pre-check and both debited. Now the
 *    Payment insert is inside the transaction and guarded by Payment.tripId
 *    @unique, so the loser's INSERT raises P2002, the whole transaction
 *    (including its balance decrement) rolls back, and the wallet moves exactly
 *    once. A fast-path check also returns AlreadyChargedError for the common,
 *    non-racing duplicate so the caller gets a clean 409.
 *
 * The guarded conditional decrement (balance must still be >= the amount)
 * additionally prevents an overdraw under concurrency.
 */
export async function chargeWalletForRide(params: {
  walletId: string;
  amountCents: number;
  tripId: string;
  riderId: string;
  /** The tax-inclusive fare recorded on the Payment row (display/receipt). */
  fareAmount: number;
}) {
  const { walletId, amountCents, tripId, riderId, fareAmount } = params;
  return prisma.$transaction(async (tx) => {
    const existing = await tx.payment.findUnique({ where: { tripId } });
    if (existing) throw new AlreadyChargedError();

    const updated = await tx.walletAccount.updateMany({
      where: { id: walletId, balanceCents: { gte: amountCents } },
      data: { balanceCents: { decrement: amountCents } },
    });
    if (updated.count === 0) throw new InsufficientFundsError();

    await tx.walletTransaction.create({
      data: { walletId, type: "RIDE_PAYMENT", status: "COMPLETED", amountCents: -amountCents, tripId },
    });

    // Guarded by Payment.tripId @unique — a concurrent second charge for the
    // same trip fails here and rolls back the debit above.
    return tx.payment.create({
      data: {
        tripId,
        userId: riderId,
        amount: fareAmount,
        method: "WALLET",
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    });
  });
}

/** Same guarantees as chargeWalletForRide, for a courier delivery. */
export async function chargeWalletForDelivery(params: {
  walletId: string;
  amountCents: number;
  courierRequestId: string;
  senderId: string;
  /** The fare recorded on the Payment row (display/receipt). */
  fareAmount: number;
}) {
  const { walletId, amountCents, courierRequestId, senderId, fareAmount } = params;
  return prisma.$transaction(async (tx) => {
    const existing = await tx.payment.findUnique({ where: { courierRequestId } });
    if (existing) throw new AlreadyChargedError();

    const updated = await tx.walletAccount.updateMany({
      where: { id: walletId, balanceCents: { gte: amountCents } },
      data: { balanceCents: { decrement: amountCents } },
    });
    if (updated.count === 0) throw new InsufficientFundsError();

    await tx.walletTransaction.create({
      data: { walletId, type: "DELIVERY_PAYMENT", status: "COMPLETED", amountCents: -amountCents, courierRequestId },
    });

    return tx.payment.create({
      data: {
        courierRequestId,
        userId: senderId,
        amount: fareAmount,
        method: "WALLET",
        status: "SUCCEEDED",
        paidAt: new Date(),
      },
    });
  });
}
