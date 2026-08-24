/**
 * Driver payout calculation and management service.
 *
 * Handles weekly/monthly payout calculations based on completed trips,
 * application fees, and driver subscription status.
 */

import { Prisma, type Payout } from "@prisma/client";
import { prisma } from "../db/prisma";
import { decryptField, maskLast4 } from "../lib/encryption";
import { env } from "../config/env";
import { withBypass } from "../lib/rls";

const PRISMA_UNIQUE_CONSTRAINT_VIOLATION = "P2002";

function isDuplicatePayoutError(err: unknown): boolean {
  return err instanceof Prisma.PrismaClientKnownRequestError && err.code === PRISMA_UNIQUE_CONSTRAINT_VIOLATION;
}

type PayoutWithDriverBank = Prisma.PayoutGetPayload<{
  include: { driver: { include: { bankAccount: true } } };
}>;

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
 * Only includes COMPLETED trips where driver was not suspended.
 */
export async function calculatePayoutForPeriod(
  driverId: string,
  period: string, // e.g., "2024-07" for July 2024
): Promise<PayoutCalculation> {
  const [year, month] = period.split("-");
  const startDate = new Date(`${year}-${month}-01`);
  const endDate = new Date(startDate);
  endDate.setMonth(endDate.getMonth() + 1);

  // Get all completed trips for this driver in the period. The `payment`
  // include is a join into the RLS-protected Payment table, so this needs
  // bypass context — without it, RLS wouldn't error, it would just make
  // trip.payment silently come back null for every trip.
  const trips = await withBypass((tx) =>
    tx.trip.findMany({
      where: {
        driverId,
        status: "COMPLETED",
        completedAt: {
          gte: startDate,
          lt: endDate,
        },
      },
      include: {
        payment: true,
      },
    }),
  );

  // Sum up all successful payments from these trips
  const grossAmount = trips.reduce((sum, trip) => {
    return sum + (trip.payment?.status === "SUCCEEDED" ? trip.payment.amount : 0);
  }, 0);

  const platformFee = grossAmount * env.PLATFORM_FEE_PERCENT;

  // Check if driver has active subscription (subscription fee offset)
  const subscription = await prisma.driverSubscription.findUnique({
    where: { driverId },
    include: { plan: true },
  });

  const subscriptionFee = subscription?.status === "ACTIVE" ? subscription.plan?.priceMonthly || 0 : 0;

  // Net = Gross - Platform Fee - Subscription Fee
  const netAmount = Math.max(0, grossAmount - platformFee - subscriptionFee);

  return {
    driverId,
    grossAmount,
    platformFee,
    subscriptionFee,
    netAmount,
    tripsIncluded: trips.length,
    period,
  };
}

/**
 * Create a payout record (does not actually process payment to bank).
 * Separate service handles actual Stripe/payment provider integration.
 * Throws the underlying Prisma unique-constraint error (P2002) unmodified
 * if `calculation.driverId`/`period` already has a payout — callers that
 * care (the create route, generatePayoutsForPeriod) classify it with
 * isDuplicatePayoutError below rather than this function swallowing it,
 * since the right response differs by caller (409 vs. skip-and-continue).
 */
export async function createPayout(calculation: PayoutCalculation): Promise<PayoutWithDriverBank> {
  const payout = await withBypass((tx) =>
    tx.payout.create({
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
    }),
  );

  // accountNumber/routingNumber are encrypted at rest — never surface the
  // ciphertext or a decrypted full value over the API; decrypt only to
  // compute the last-4 mask, like the driver-facing routes do.
  if (payout.driver.bankAccount) {
    payout.driver.bankAccount.accountNumber = maskLast4(decryptField(payout.driver.bankAccount.accountNumber));
    payout.driver.bankAccount.routingNumber = maskLast4(decryptField(payout.driver.bankAccount.routingNumber));
  }

  return payout;
}

/**
 * Process a pending payout (mark as PROCESSING, send to Stripe, etc).
 * In production, integrate with Stripe Connect for ACH transfers.
 */
export async function processPayout(payoutId: string): Promise<Payout> {
  return withBypass(async (tx) => {
    const payout = await tx.payout.findUnique({
      where: { id: payoutId },
      include: {
        driver: {
          include: { bankAccount: true },
        },
      },
    });

    if (!payout) throw new Error("Payout not found");
    if (payout.status !== "PENDING") throw new Error("Payout must be PENDING to process");

    // TODO: Integrate with Stripe Connect or other payment provider
    // For now, simulate successful processing
    return tx.payout.update({
      where: { id: payoutId },
      data: {
        status: "PROCESSING",
        // In production, set transactionId from Stripe response
        transactionId: `stripe_payout_${Date.now()}`,
      },
    });
  });
}

/**
 * Mark a payout as completed (successful transfer to driver's bank).
 * Called from webhook handler when Stripe confirms delivery.
 */
export async function completePayout(payoutId: string, transactionId?: string): Promise<Payout> {
  return withBypass((tx) =>
    tx.payout.update({
      where: { id: payoutId },
      data: {
        status: "COMPLETED",
        completedAt: new Date(),
        transactionId: transactionId || undefined,
      },
    }),
  );
}

/**
 * Mark a payout as failed with reason.
 */
export async function failPayout(payoutId: string, reason: string): Promise<Payout> {
  return withBypass((tx) =>
    tx.payout.update({
      where: { id: payoutId },
      data: {
        status: "FAILED",
        failureReason: reason,
      },
    }),
  );
}

/**
 * Get payout history for a driver.
 */
export async function getPayoutHistory(driverId: string, limit: number = 10): Promise<Payout[]> {
  return withBypass((tx) =>
    tx.payout.findMany({
      where: { driverId },
      orderBy: { createdAt: "desc" },
      take: limit,
    }),
  );
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
      const existing = await withBypass((tx) => tx.payout.findFirst({ where: { driverId: driver.id, period } }));
      if (existing) continue;

      const calculation = await calculatePayoutForPeriod(driver.id, period);
      if (calculation.netAmount > 0) {
        const payout = await createPayout(calculation);
        payouts.push(payout);
      }
    } catch (error) {
      // A duplicate here means a concurrent /payouts/create call, or a
      // second run of this same batch job (retry after timeout, an
      // overlapping schedule, etc.), already created this driver's payout
      // for the period between the findFirst above and this create — the
      // @@unique([driverId, period]) constraint is what actually caught
      // it. Expected under concurrency, not a real failure; log the real
      // ones loudly, skip this one quietly.
      if (isDuplicatePayoutError(error)) continue;
      console.error(`Failed to create payout for driver ${driver.id}:`, error);
    }
  }

  return payouts;
}
