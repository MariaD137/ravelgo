/**
 * Driver payout calculation and management service.
 *
 * Handles weekly/monthly payout calculations based on completed trips,
 * application fees, and driver subscription status.
 */

import type { Payout, Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { roundMoney } from "../lib/money";

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
 * Create a payout record (does not actually process payment to bank).
 * Separate service handles actual Stripe/payment provider integration.
 */
type PayoutWithDriverBank = Prisma.PayoutGetPayload<{
  include: { driver: { include: { bankAccount: true } } };
}>;

export async function createPayout(calculation: PayoutCalculation): Promise<PayoutWithDriverBank> {
  const payout = await prisma.payout.create({
    data: {
      driverId: calculation.driverId,
      amount: calculation.netAmount,
      currency: "USD",
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

/**
 * Mark a pending payout as PROCESSING — i.e. an admin/ops has started an
 * actual transfer to the driver's bank account, outside this system (there
 * is no real Stripe Connect / ACH integration wired up yet: see PY-1).
 *
 * This deliberately does NOT set transactionId. It used to fabricate one
 * (`stripe_payout_${Date.now()}`) that looked like a real payment-provider
 * reference but was never sent to, or verified by, any payment provider —
 * a payout could reach COMPLETED carrying a permanent, convincing-looking
 * transactionId for a transfer that, as far as this system can actually
 * prove, never happened. completePayout() below already accepts a real
 * transactionId from its caller; that is the only place one should ever be
 * recorded, and only once a real transfer reference exists to record.
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

  const processed = await prisma.payout.update({
    where: { id: payoutId },
    data: { status: "PROCESSING" },
  });

  return processed;
}

/**
 * Mark a payout as completed (successful transfer to driver's bank).
 *
 * `transactionId` is required (SE-4): there is no live Stripe Connect/ACH
 * integration yet (see PY-1), so this is called by an admin confirming a
 * transfer they made outside this system, and the real bank/wire reference
 * is the only thing that makes that confirmation checkable later. A payout
 * can only ever reach COMPLETED carrying a real, unique transaction
 * reference — never a fabricated one (see processPayout above) and never
 * none at all.
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
