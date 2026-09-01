/**
 * Driver payout calculation and management service.
 *
 * Handles weekly/monthly payout calculations based on completed trips,
 * application fees, and driver subscription status.
 */

import type { Payout, Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { PLATFORM_COMMISSION_RATE, roundMoney } from "../lib/money";

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
 *
 * `driverId` here is the caller-facing identifier — User.id, the same value
 * stored on Payout.driverId and DriverBankAccount.driverId (both FK ->
 * User.id, see prisma/schema.prisma). Trip.driverId and
 * DriverSubscription.driverId are FKs to the separate Driver.id, so that
 * record is resolved first rather than querying those tables with the
 * User.id directly — passing the wrong id silently matched zero rows
 * (every trip/subscription lookup below would return nothing), which is
 * exactly the bug this comment is here to prevent regressing.
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
  // no trips or subscription possibly exist for them either.
  const trips = driverProfile
    ? await prisma.trip.findMany({
        where: {
          driverId: driverProfile.id,
          status: "COMPLETED",
          completedAt: {
            gte: startDate,
            lt: endDate,
          },
        },
        include: {
          payment: true,
        },
      })
    : [];

  // Sum up all successful payments from these trips. payment.amount is the
  // tax-inclusive total the rider paid (card or wallet), so commission below
  // is taken on the tax-inclusive total, exactly as the product requires.
  const grossAmount = roundMoney(
    trips.reduce((sum, trip) => {
      return sum + (trip.payment?.status === "SUCCEEDED" ? trip.payment.amount : 0);
    }, 0),
  );

  // RavelGo keeps PLATFORM_COMMISSION_RATE (25%); the rest is the driver's.
  const platformFee = roundMoney(grossAmount * PLATFORM_COMMISSION_RATE);

  // Check if driver has active subscription (subscription fee offset)
  const subscription = driverProfile
    ? await prisma.driverSubscription.findUnique({
        where: { driverId: driverProfile.id },
        include: { plan: true },
      })
    : null;

  const subscriptionFee = subscription?.status === "ACTIVE" ? subscription.plan?.priceMonthly || 0 : 0;

  // Net = Gross - Platform Commission - Subscription Fee
  const netAmount = Math.max(0, roundMoney(grossAmount - platformFee - subscriptionFee));

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
 * Process a pending payout (mark as PROCESSING, send to Stripe, etc).
 * In production, integrate with Stripe Connect for ACH transfers.
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

  // TODO: Integrate with Stripe Connect or other payment provider
  // For now, simulate successful processing
  const processed = await prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: "PROCESSING",
      // In production, set transactionId from Stripe response
      transactionId: `stripe_payout_${Date.now()}`,
    },
  });

  return processed;
}

/**
 * Mark a payout as completed (successful transfer to driver's bank).
 * Called from webhook handler when Stripe confirms delivery.
 */
export async function completePayout(payoutId: string, transactionId?: string): Promise<Payout> {
  return prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: "COMPLETED",
      completedAt: new Date(),
      transactionId: transactionId || undefined,
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
