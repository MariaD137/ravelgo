/**
 * Driver payout calculation and management service.
 *
 * Handles weekly/monthly payout calculations based on completed trips,
 * application fees, and driver subscription status.
 */

import type { Payout, Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { roundMoney, toCents } from "../lib/money";
import { PaystackApiError, paystackClient } from "../billing/paystack";
import { notifyUser } from "../lib/notifications";

interface PayoutCalculation {
  driverId: string;
  grossAmount: number; // Total from completed trips
  platformFee: number; // Percentage taken by RavelGo
  subscriptionFee: number; // Monthly subscription if active
  netAmount: number; // Gross - fees
  tripsIncluded: number;
  period: string;
}

/**
 * Calculate payout for a driver for a given period (YYYY-MM for monthly, YYYY-W## for weekly).
 *
 * Sources gross/commission/driver-earnings from the FinancialTransaction
 * ledger (services/ledger.ts) — the amounts actually locked in at each
 * transaction's settlement — rather than recomputing commission from
 * whatever the current CommissionConfig says (spec #14: a rate change must
 * never retroactively change an already-settled transaction's split).
 *
 * CASH transactions are deliberately EXCLUDED from this payout: a cash
 * fare's driver-earnings share never passed through RavelGo (the driver
 * already physically holds it), so it must never be paid out again via bank
 * transfer. Only its commission is owed to RavelGo, tracked separately by
 * the cash-remittance reconciliation (cash.routes.ts) — excluding it here is
 * exactly what stops that commission being deducted twice (once from this
 * payout, once from the driver's physical cash hand-in).
 *
 * `driverId` here is the caller-facing identifier — User.id, the same value
 * stored on Payout.driverId and DriverBankAccount.driverId (both FK ->
 * User.id, see prisma/schema.prisma). Trip.driverId, FinancialTransaction.driverId
 * and DriverSubscription.driverId are FKs to the separate Driver.id, so that
 * record is resolved first rather than querying those tables with the
 * User.id directly — passing the wrong id silently matched zero rows
 * (every lookup below would return nothing), which is exactly the bug this
 * comment is here to prevent regressing.
 */
export async function calculatePayoutForPeriod(
  driverId: string,
  period: string, // e.g., "2024-07" for July 2024
): Promise<PayoutCalculation> {
  const [year, month] = period.split("-");
  const startDate = new Date(`${year}-${month}-01`);
  const endDate = new Date(startDate);
  endDate.setMonth(endDate.getMonth() + 1);

  const driverProfile = await prisma.driver.findUnique({ where: { userId: driverId } });

  // No Driver profile (User exists but never completed driver onboarding) ->
  // no ledger rows or subscription possibly exist for them either.
  const ledgerRows = driverProfile
    ? await prisma.financialTransaction.findMany({
        where: {
          driverId: driverProfile.id,
          type: { in: ["RIDE_FARE", "DELIVERY_FARE", "REFUND"] },
          status: "SETTLED",
          createdAt: { gte: startDate, lt: endDate },
        },
      })
    : [];

  const payableRows = ledgerRows.filter((r) => r.paymentMethod !== "CASH");

  let grossAmount = 0;
  let platformFee = 0;
  let driverGrossEarnings = 0;
  let tripsIncluded = 0;
  for (const row of payableRows) {
    // A REFUND row's grossAmount is the (positive) amount given back — it
    // reduces gross rather than adding to it; its commissionAmount/
    // driverEarnings are already stored negative (services/ledger.ts), so
    // summing those two fields needs no special-casing.
    grossAmount += row.type === "REFUND" ? -row.grossAmount : row.grossAmount;
    platformFee += row.commissionAmount;
    driverGrossEarnings += row.driverEarnings;
    if (row.type !== "REFUND") tripsIncluded += 1;
  }
  grossAmount = roundMoney(grossAmount);
  platformFee = roundMoney(platformFee);
  driverGrossEarnings = roundMoney(driverGrossEarnings);

  // Check if driver has active subscription (subscription fee offset)
  const subscription = driverProfile
    ? await prisma.driverSubscription.findUnique({
        where: { driverId: driverProfile.id },
        include: { plan: true },
      })
    : null;

  const subscriptionFee = subscription?.status === "ACTIVE" ? subscription.plan?.priceMonthly || 0 : 0;

  // Net = (already-commissioned) driver earnings - Subscription Fee
  const netAmount = Math.max(0, roundMoney(driverGrossEarnings - subscriptionFee));

  return {
    driverId,
    grossAmount,
    platformFee,
    subscriptionFee,
    netAmount,
    tripsIncluded,
    period,
  };
}

/**
 * Create a payout record (does not actually process payment to bank —
 * processPayout() below does, via a real Paystack transfer when the
 * driver's bank account has a bank code on file).
 */
type PayoutWithDriverBank = Prisma.PayoutGetPayload<{
  include: { driver: { include: { bankAccount: true } } };
}>;

export async function createPayout(calculation: PayoutCalculation): Promise<PayoutWithDriverBank> {
  const payout = await prisma.payout.create({
    data: {
      driverId: calculation.driverId,
      amount: calculation.netAmount,
      currency: "NGN",
      status: "PENDING",
      period: calculation.period,
    },
    include: {
      driver: {
        include: { bankAccount: true },
      },
    },
  });

  return payout;
}

/** processPayout() couldn't initiate a real Paystack transfer — the payout stays PENDING, unchanged. Maps to 502. */
export class PayoutTransferFailedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PayoutTransferFailedError";
  }
}

/**
 * Mark a pending payout as PROCESSING and, when the driver's bank account
 * has a Paystack bank code on file, actually initiate a real Paystack
 * Transfer — closing PY-1 (there used to be no live provider integration at
 * all here; processPayout() only flipped a status and completePayout()
 * required an admin to paste a reference from a transfer made entirely
 * outside this system). The transfer's outcome (transfer.success /
 * transfer.failed) arrives on the same signed webhook billing.routes.ts
 * already handles for charges, and finalizePayoutFromTransferWebhook()
 * below applies it.
 *
 * Falls back to the old manual-reference flow (PROCESSING with no
 * transactionId, left for an admin to confirm via completePayout()) when the
 * driver has no bank code on file yet — this only happens for bank accounts
 * saved before the Paystack fields existed, or a bank Paystack doesn't
 * support transfers to. It is never a silent failure: the caller can tell
 * the two cases apart via the returned payout's `provider` field (PAYSTACK
 * vs null).
 */
export async function processPayout(payoutId: string): Promise<Payout> {
  const payout = await prisma.payout.findUnique({
    where: { id: payoutId },
    include: {
      driver: {
        include: { bankAccount: true },
      },
    },
  });

  if (!payout) throw new Error("Payout not found");
  if (payout.status !== "PENDING") throw new Error("Payout must be PENDING to process");

  const account = payout.driver.bankAccount;
  if (!account || !account.bankCode) {
    return prisma.payout.update({ where: { id: payoutId }, data: { status: "PROCESSING" } });
  }

  try {
    let recipientCode = account.paystackRecipientCode;
    if (!recipientCode) {
      // Confirms the account number is real before RavelGo ever tries to
      // send money to it — Paystack itself requires this before a transfer
      // recipient can be created.
      await paystackClient.resolveAccountNumber(account.accountNumber, account.bankCode);
      const recipient = await paystackClient.createTransferRecipient({
        name: account.accountHolderName,
        accountNumber: account.accountNumber,
        bankCode: account.bankCode,
      });
      recipientCode = recipient.recipientCode;
      await prisma.driverBankAccount.update({
        where: { id: account.id },
        data: { paystackRecipientCode: recipientCode },
      });
    }

    const reference = `ravelgo_payout_${payout.id}`;
    await paystackClient.initiateTransfer({
      amountKobo: toCents(payout.amount),
      recipientCode,
      reference,
      reason: `RavelGo payout ${payout.period}`,
    });

    return prisma.payout.update({
      where: { id: payoutId },
      data: { status: "PROCESSING", provider: "PAYSTACK", transactionId: reference },
    });
  } catch (err) {
    const message = err instanceof PaystackApiError ? err.message : "Failed to initiate transfer";
    throw new PayoutTransferFailedError(message);
  }
}

/**
 * Finalize a payout that processPayout() initiated a real Paystack transfer
 * for, driven by the transfer.success / transfer.failed webhook
 * (billing.routes.ts). Idempotent against a duplicate webhook delivery for
 * the same reference: only a payout still PROCESSING is matched, so a
 * redelivered event is a no-op the second time (same pattern as the
 * charge.success handling in billing.routes.ts).
 */
export async function finalizePayoutFromTransferWebhook(
  reference: string,
  succeeded: boolean,
  failureReason?: string,
): Promise<void> {
  const payout = await prisma.payout.findFirst({ where: { transactionId: reference, status: "PROCESSING" } });
  if (!payout) return; // unknown, already finalized, or a manual (non-Paystack) reference

  const { count } = await prisma.payout.updateMany({
    where: { id: payout.id, status: "PROCESSING" },
    data: succeeded
      ? { status: "COMPLETED", completedAt: new Date() }
      : { status: "FAILED", failureReason: failureReason ?? "Transfer failed" },
  });
  if (count !== 1) return;

  await notifyUser(
    payout.driverId,
    succeeded ? "PAYOUT_COMPLETED" : "PAYOUT_FAILED",
    succeeded ? "Payout sent" : "Payout failed",
    succeeded
      ? `Your payout of ${payout.amount} for ${payout.period} has been sent to your bank account.`
      : `Your payout of ${payout.amount} for ${payout.period} could not be sent. RavelGo support has been notified.`,
    { type: "PAYOUT", id: payout.id },
  );
}

/**
 * Manually mark a payout as completed (successful transfer to driver's
 * bank) — the fallback path for a payout processPayout() couldn't
 * automate (no Paystack bank code on file; see PY-1). A payout that DID go
 * through Paystack finalizes itself via finalizePayoutFromTransferWebhook()
 * instead, driven by the transfer.success webhook, never this function.
 *
 * `transactionId` is required (SE-4): this is called by an admin confirming
 * a transfer they made outside this system, and the real bank/wire
 * reference is the only thing that makes that confirmation checkable
 * later. A payout can only ever reach COMPLETED this way carrying a real,
 * unique transaction reference — never a fabricated one (see processPayout
 * above) and never none at all.
 */
export async function completePayout(payoutId: string, transactionId: string): Promise<Payout> {
  return prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: "COMPLETED",
      completedAt: new Date(),
      transactionId,
    },
  });
}

/**
 * Mark a payout as failed with reason.
 */
export async function failPayout(payoutId: string, reason: string): Promise<Payout> {
  return prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: "FAILED",
      failureReason: reason,
    },
  });
}

/**
 * Get payout history for a driver.
 */
export async function getPayoutHistory(driverId: string, limit: number = 10): Promise<Payout[]> {
  return prisma.payout.findMany({
    where: { driverId },
    orderBy: { createdAt: "desc" },
    take: limit,
  });
}

/**
 * Calculate and create pending payouts for all active drivers for a given period.
 * Typically run weekly/monthly via scheduled job.
 */
export async function generatePayoutsForPeriod(period: string): Promise<PayoutWithDriverBank[]> {
  // Get all active drivers
  const drivers = await prisma.user.findMany({
    where: { role: "DRIVER", suspended: false },
  });

  const payouts: PayoutWithDriverBank[] = [];
  for (const driver of drivers) {
    try {
      // Idempotency (P0 #6): if this driver already has a payout for the
      // period, skip — a re-run to recover from a partial failure must not
      // pay anyone twice. The @@unique([driverId, period]) index is the
      // authoritative backstop; this check just avoids the wasted work and a
      // noisy conflict for the common re-run case.
      const already = await prisma.payout.findUnique({
        where: { driverId_period: { driverId: driver.id, period } },
      });
      if (already) continue;

      const calculation = await calculatePayoutForPeriod(driver.id, period);
      if (calculation.netAmount > 0) {
        const payout = await createPayout(calculation);
        payouts.push(payout);
      }
    } catch (error) {
      // A P2002 here means a concurrent run created this driver's payout first
      // — that is the constraint doing its job, not a failure to surface. Any
      // other error is a genuine per-driver problem worth logging while the
      // rest of the batch proceeds.
      if (error && typeof error === "object" && (error as { code?: string }).code === "P2002") continue;
      console.error(`Failed to create payout for driver ${driver.id}:`, error);
    }
  }

  return payouts;
}
