/**
 * Driver payout calculation and management service.
 *
 * Handles weekly/monthly payout calculations based on completed trips,
 * application fees, and driver subscription status.
 */

import { prisma } from "../db/prisma";

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

  // Get all completed trips for this driver in the period
  const trips = await prisma.trip.findMany({
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
  });

  // Sum up all successful payments from these trips
  const grossAmount = trips.reduce((sum, trip) => {
    return sum + (trip.payment?.status === "SUCCEEDED" ? trip.payment.amount : 0);
  }, 0);

  // Platform takes 20% commission (configurable)
  const platformFeePercent = 0.2;
  const platformFee = grossAmount * platformFeePercent;

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
 */
export async function createPayout(calculation: PayoutCalculation) {
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
export async function processPayout(payoutId: string) {
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
export async function completePayout(payoutId: string, transactionId?: string) {
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
export async function failPayout(payoutId: string, reason: string) {
  return prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: "FAILED",
      failureReason: reason,
    },
  });
}

/**
 * Calculate and create pending payouts for all active drivers for a given period.
 * Typically run weekly/monthly via scheduled job.
 */
export async function generatePayoutsForPeriod(period: string) {
  // Get all active drivers
  const drivers = await prisma.user.findMany({
    where: { role: "DRIVER", suspended: false },
  });

  const payouts: Awaited<ReturnType<typeof createPayout>>[] = [];
  for (const driver of drivers) {
    try {
      const calculation = await calculatePayoutForPeriod(driver.id, period);
      if (calculation.netAmount > 0) {
        const payout = await createPayout(calculation);
        payouts.push(payout);
      }
    } catch (error) {
      console.error(`Failed to create payout for driver ${driver.id}:`, error);
    }
  }

  return payouts;
}
