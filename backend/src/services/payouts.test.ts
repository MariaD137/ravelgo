import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { createPayout, generatePayoutsForPeriod } from "./payouts";

// P0 #6: a driver may never receive two payouts for one period. resetDb clears
// Payout transitively (Payout.driverId -> User onDelete Cascade).
beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

const PERIOD = "2026-05";

// Build a driver (User + Driver profile) with one COMPLETED, SUCCEEDED-paid
// trip inside the period, so calculatePayoutForPeriod yields netAmount > 0.
async function seedPaidDriver(tag: string) {
  const user = await prisma.user.create({
    data: { cognitoSub: `drv-${tag}`, role: "DRIVER", firstName: "D", lastName: tag, email: `${tag}@example.com`, suspended: false },
  });
  const rider = await prisma.user.create({
    data: { cognitoSub: `rdr-${tag}`, role: "RIDER", firstName: "R", lastName: tag, email: `r-${tag}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 100,
      finalFare: 100,
      status: "COMPLETED",
      completedAt: new Date("2026-05-15T10:00:00Z"),
    },
  });
  const payment = await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 100, method: "CARD", status: "SUCCEEDED", paidAt: new Date() },
  });
  // calculatePayoutForPeriod now sources gross/commission/driver-earnings
  // from the FinancialTransaction ledger (services/ledger.ts), not raw
  // Payment rows directly — this is what recordRideCommission() would have
  // written had the trip gone through the real settlement flow.
  await prisma.financialTransaction.create({
    data: {
      type: "RIDE_FARE",
      tripId: trip.id,
      paymentId: payment.id,
      customerId: rider.id,
      driverId: driver.id,
      grossAmount: 100,
      commissionRate: 0.2,
      commissionAmount: 20,
      driverEarnings: 80,
      paymentMethod: "CARD",
      status: "SETTLED",
      // Backdated to land inside PERIOD ("2026-05") — createdAt is what
      // calculatePayoutForPeriod actually buckets by (when the payment
      // settled), not trip.completedAt, so this has to match that, not
      // whatever "now" happens to be when the test runs.
      createdAt: new Date("2026-05-15T10:00:00Z"),
      completedAt: new Date("2026-05-15T10:00:00Z"),
    },
  });
  return user; // Payout.driverId is User.id
}

test("generatePayoutsForPeriod is idempotent — a re-run creates no duplicate payouts", async () => {
  await seedPaidDriver("a");

  const first = await generatePayoutsForPeriod(PERIOD);
  assert.equal(first.length, 1);

  // Re-run (e.g. recovering from a partial failure): must create nothing new.
  const second = await generatePayoutsForPeriod(PERIOD);
  assert.equal(second.length, 0);

  assert.equal(await prisma.payout.count(), 1);
});

test("concurrent payout generation for one period still yields exactly one payout per driver", async () => {
  await seedPaidDriver("b");

  // Two runs racing: the @@unique([driverId, period]) index guarantees one wins.
  await Promise.all([generatePayoutsForPeriod(PERIOD), generatePayoutsForPeriod(PERIOD)]);

  assert.equal(await prisma.payout.count(), 1);
});

test("a direct duplicate createPayout for the same driver+period is rejected by the DB", async () => {
  const driver = await seedPaidDriver("c");
  const calc = { driverId: driver.id, grossAmount: 100, platformFee: 25, subscriptionFee: 0, netAmount: 75, tripsIncluded: 1, period: PERIOD };

  await createPayout(calc);
  await assert.rejects(() => createPayout(calc), (err: { code?: string }) => err.code === "P2002");
  assert.equal(await prisma.payout.count(), 1);
});

test("distinct drivers and distinct periods each get their own payout", async () => {
  await seedPaidDriver("d1");
  await seedPaidDriver("d2");

  const may = await generatePayoutsForPeriod(PERIOD);
  assert.equal(may.length, 2); // two drivers, one period each

  // A different period is independent — same drivers can be paid again for
  // it. calculatePayoutForPeriod buckets by when the ledger entry actually
  // settled (FinancialTransaction.createdAt), not trip.completedAt — moving
  // both keeps the fixture consistent with a trip whose payment settled
  // later, in June.
  await prisma.trip.updateMany({ data: { completedAt: new Date("2026-06-10T10:00:00Z") } });
  await prisma.financialTransaction.updateMany({ data: { createdAt: new Date("2026-06-10T10:00:00Z") } });
  const june = await generatePayoutsForPeriod("2026-06");
  assert.equal(june.length, 2);

  assert.equal(await prisma.payout.count(), 4);
});
