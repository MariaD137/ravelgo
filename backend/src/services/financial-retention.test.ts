import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";

// P0 #12: financial history must survive. A user with payout / wallet / trip
// history cannot be hard-deleted (the FKs are ON DELETE RESTRICT); accounts are
// deactivated with deletedAt instead, which preserves every ledger row.
beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function seedDriverWithHistory() {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "drv-fin", role: "DRIVER", firstName: "D", lastName: "F", email: "drvfin@example.com" },
  });
  const rider = await prisma.user.create({
    data: { cognitoSub: "rdr-fin", role: "RIDER", firstName: "R", lastName: "F", email: "rdrfin@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  await prisma.walletAccount.create({ data: { userId: driverUser.id, balanceCents: 2500 } });
  await prisma.payout.create({ data: { driverId: driverUser.id, amount: 75, period: "2026-05", status: "COMPLETED" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 100, finalFare: 100, status: "COMPLETED" },
  });
  return { driverUser, rider, driver, trip };
}

test("a driver User with a payout cannot be hard-deleted; the payout survives", async () => {
  const { driverUser } = await seedDriverWithHistory();
  await assert.rejects(
    () => prisma.user.delete({ where: { id: driverUser.id } }),
    (err: { code?: string }) => err.code === "P2003" || err.code === "P2014",
    "deleting a user with financial history must be blocked by the DB",
  );
  assert.equal(await prisma.payout.count(), 1, "payout preserved");
  assert.equal(await prisma.walletAccount.count(), 1, "wallet preserved");
});

test("a completed trip keeps its driver link — the driver row cannot be deleted out from under it", async () => {
  const { driver } = await seedDriverWithHistory();
  await assert.rejects(
    () => prisma.driver.delete({ where: { id: driver.id } }),
    (err: { code?: string }) => err.code === "P2003" || err.code === "P2014",
  );
  const trip = await prisma.trip.findFirst({ where: { driverId: driver.id } });
  assert.ok(trip, "completed trip still linked to its driver");
});

test("soft-deleting the user (deletedAt) succeeds and preserves the whole ledger", async () => {
  const { driverUser } = await seedDriverWithHistory();
  const deactivated = await prisma.user.update({
    where: { id: driverUser.id },
    data: { deletedAt: new Date() },
  });
  assert.ok(deactivated.deletedAt, "user is marked deleted");
  // Everything financial is intact.
  assert.equal(await prisma.payout.count(), 1);
  assert.equal(await prisma.walletAccount.count(), 1);
  assert.equal(await prisma.trip.count(), 1);
});
