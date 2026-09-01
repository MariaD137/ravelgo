import { prisma } from "../db/prisma";

/**
 * Credit a wallet for a confirmed Stripe top-up. Called from the signed
 * webhook only, never from a client path. Idempotent: Stripe can deliver the
 * same event more than once, so a top-up already marked COMPLETED is a no-op
 * and the balance is never double-credited.
 */
export async function creditWalletFromTopup(providerReference: string): Promise<void> {
  await prisma.$transaction(async (tx) => {
    const txn = await tx.walletTransaction.findUnique({ where: { providerReference } });
    if (!txn || txn.type !== "TOPUP" || txn.status !== "PENDING") return; // unknown or already handled
    await tx.walletTransaction.update({ where: { id: txn.id }, data: { status: "COMPLETED" } });
    await tx.walletAccount.update({
      where: { id: txn.walletId },
      data: { balanceCents: { increment: txn.amountCents } },
    });
  });
}

/** Mark a top-up FAILED when Stripe reports the charge failed. Idempotent. */
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

/**
 * Debit a wallet for a ride, atomically. The conditional updateMany (balance
 * must still be >= the amount) means two concurrent charges can't both spend
 * the same funds — if the guarded update touches zero rows, the balance moved
 * out from under us and we reject rather than overdraw.
 */
export async function debitWalletForRide(
  walletId: string,
  amountCents: number,
  tripId: string,
): Promise<void> {
  await prisma.$transaction(async (tx) => {
    const updated = await tx.walletAccount.updateMany({
      where: { id: walletId, balanceCents: { gte: amountCents } },
      data: { balanceCents: { decrement: amountCents } },
    });
    if (updated.count === 0) throw new InsufficientFundsError();

    await tx.walletTransaction.create({
      data: {
        walletId,
        type: "RIDE_PAYMENT",
        status: "COMPLETED",
        amountCents: -amountCents,
        tripId,
      },
    });
  });
}
