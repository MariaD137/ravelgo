import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { withBypass, withUserContext } from "./rls";

beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  return user;
}

// These tests exercise the database policy directly, not through an HTTP
// route — the point is to prove FORCE ROW LEVEL SECURITY is actually
// enforcing isolation, independent of whatever `where` clause the calling
// code happens to write. A route-level test could pass for the wrong
// reason (an app-layer where clause papering over RLS being silently
// disabled); these can't.

test("a query with no session context set sees zero rows, even though rows exist", async () => {
  const driver = await createDriver("driver-rls-1");
  await withBypass((tx) => tx.payout.create({ data: { driverId: driver.id, amount: 50, period: "2026-01", status: "PENDING" } }));

  // Deliberately the raw, unscoped client — no withUserContext/withBypass.
  const rows = await prisma.payout.findMany({ where: { driverId: driver.id } });
  assert.equal(rows.length, 0, "FORCE RLS should hide the row without app.bypass or a matching app.user_id set");
});

test("withUserContext(ownerId) sees only that owner's rows, with no where clause at all", async () => {
  const driverA = await createDriver("driver-rls-2");
  const driverB = await createDriver("driver-rls-3");
  await withBypass(async (tx) => {
    await tx.payout.create({ data: { driverId: driverA.id, amount: 10, period: "2026-01", status: "PENDING" } });
    await tx.payout.create({ data: { driverId: driverB.id, amount: 20, period: "2026-01", status: "PENDING" } });
  });

  // No `where` at all — if RLS weren't doing the filtering, this would
  // return both drivers' payouts.
  const rowsForA = await withUserContext(driverA.id, (tx) => tx.payout.findMany());
  assert.equal(rowsForA.length, 1);
  assert.equal(rowsForA[0].driverId, driverA.id);
  assert.equal(rowsForA[0].amount, 10);
});

test("withUserContext cannot write a row owned by a different user (WITH CHECK)", async () => {
  const driverA = await createDriver("driver-rls-4");
  const driverB = await createDriver("driver-rls-5");

  await assert.rejects(
    () => withUserContext(driverA.id, (tx) => tx.payout.create({ data: { driverId: driverB.id, amount: 30, period: "2026-01", status: "PENDING" } })),
    /row-level security/i,
  );
});

test("withBypass sees rows across every owner", async () => {
  const driverA = await createDriver("driver-rls-6");
  const driverB = await createDriver("driver-rls-7");
  await withBypass(async (tx) => {
    await tx.payout.create({ data: { driverId: driverA.id, amount: 10, period: "2026-01", status: "PENDING" } });
    await tx.payout.create({ data: { driverId: driverB.id, amount: 20, period: "2026-01", status: "PENDING" } });
  });

  const all = await withBypass((tx) => tx.payout.findMany());
  assert.equal(all.length, 2);
});

test("DriverBankAccount and Payment are isolated the same way as Payout", async () => {
  const driverA = await createDriver("driver-rls-8");
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-rls-1", role: "RIDER", firstName: "R", lastName: "I", email: "rider-rls-1@example.com" },
  });

  await withBypass(async (tx) => {
    await tx.driverBankAccount.create({
      data: { driverId: driverA.id, accountHolderName: "A", bankName: "B", accountNumber: "enc", routingNumber: "enc" },
    });
  });
  const noContextBank = await prisma.driverBankAccount.findMany();
  assert.equal(noContextBank.length, 0);
  const scopedBank = await withUserContext(driverA.id, (tx) => tx.driverBankAccount.findMany());
  assert.equal(scopedBank.length, 1);

  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 10, status: "COMPLETED" },
  });
  await withBypass((tx) => tx.payment.create({ data: { tripId: trip.id, userId: rider.id, amount: 10, status: "SUCCEEDED" } }));
  const noContextPayment = await prisma.payment.findMany();
  assert.equal(noContextPayment.length, 0);
  const scopedPayment = await withUserContext(rider.id, (tx) => tx.payment.findMany());
  assert.equal(scopedPayment.length, 1);
});
