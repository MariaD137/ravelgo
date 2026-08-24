/**
 * Direct test of the RLS session-context mechanism itself (withUserContext /
 * withBypass) against the three FORCE ROW LEVEL SECURITY tables — see
 * prisma/migrations/*_enable_rls_financial_tables and lib/rls.ts.
 *
 * Route-level tests (payments.routes.test.ts, payouts.routes.test.ts) prove
 * this works end-to-end through HTTP for the cases those routes exercise.
 * This file proves the underlying mechanism itself, for all three
 * protected tables, independent of any route: with no context set a query
 * sees nothing; withUserContext scopes strictly to the given owner; a wrong
 * owner id sees nothing; withBypass sees everything; and the same scoping
 * applies to writes (WITH CHECK), not just reads (USING).
 */
import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { withBypass, withUserContext } from "./rls";

beforeEach(resetDb);
afterEach(resetDb);
after(async () => {
  await prisma.$disconnect();
});

async function createRiderAndDriver() {
  const rider = await prisma.user.create({
    data: { cognitoSub: `rls-rider-${Date.now()}-${Math.random()}`, role: "RIDER", firstName: "R", lastName: "I", email: `rls-rider-${Date.now()}-${Math.random()}@example.com` },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: `rls-driver-${Date.now()}-${Math.random()}`, role: "DRIVER", firstName: "D", lastName: "R", email: `rls-driver-${Date.now()}-${Math.random()}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  return { rider, driverUser, driver };
}

test("Payment: no context set sees nothing, even though rows exist", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  await withBypass((tx) => tx.payment.create({ data: { tripId: trip.id, userId: rider.id, amount: 10, status: "SUCCEEDED" } }));

  // A plain query, run with no RLS session variables set at all (not even
  // inside withUserContext/withBypass), must see zero rows — never an
  // error, never someone else's row. This is the actual backstop: an
  // app-layer bug that forgets to scope a query fails closed.
  const rows = await prisma.payment.findMany();
  assert.equal(rows.length, 0);
});

test("Payment: withUserContext scopes strictly to the given owner", async () => {
  const { rider: riderA } = await createRiderAndDriver();
  const { rider: riderB, driver } = await createRiderAndDriver();
  const tripA = await prisma.trip.create({
    data: { riderId: riderA.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  const tripB = await prisma.trip.create({
    data: { riderId: riderB.id, driverId: driver.id, pickup: "C", destination: "D", estimatedFare: 20, status: "COMPLETED" },
  });
  await withBypass((tx) => tx.payment.create({ data: { tripId: tripA.id, userId: riderA.id, amount: 10, status: "SUCCEEDED" } }));
  await withBypass((tx) => tx.payment.create({ data: { tripId: tripB.id, userId: riderB.id, amount: 20, status: "SUCCEEDED" } }));

  const asRiderA = await withUserContext(riderA.id, (tx) => tx.payment.findMany());
  assert.equal(asRiderA.length, 1);
  assert.equal(asRiderA[0].userId, riderA.id);
  assert.equal(asRiderA[0].amount, 10);

  const asRiderB = await withUserContext(riderB.id, (tx) => tx.payment.findMany());
  assert.equal(asRiderB.length, 1);
  assert.equal(asRiderB[0].userId, riderB.id);
  assert.equal(asRiderB[0].amount, 20);
});

test("Payment: withUserContext for a user who owns no payments sees an empty list, not an error", async () => {
  const { rider: owner, driver } = await createRiderAndDriver();
  const { rider: stranger } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: owner.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  await withBypass((tx) => tx.payment.create({ data: { tripId: trip.id, userId: owner.id, amount: 10, status: "SUCCEEDED" } }));

  const asStranger = await withUserContext(stranger.id, (tx) => tx.payment.findMany());
  assert.deepEqual(asStranger, []);
});

test("Payment: withBypass sees every row regardless of owner", async () => {
  const { rider: riderA, driver } = await createRiderAndDriver();
  const { rider: riderB } = await createRiderAndDriver();
  const tripA = await prisma.trip.create({
    data: { riderId: riderA.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  const tripB = await prisma.trip.create({
    data: { riderId: riderB.id, driverId: driver.id, pickup: "C", destination: "D", estimatedFare: 20, status: "COMPLETED" },
  });
  await withBypass((tx) => tx.payment.create({ data: { tripId: tripA.id, userId: riderA.id, amount: 10, status: "SUCCEEDED" } }));
  await withBypass((tx) => tx.payment.create({ data: { tripId: tripB.id, userId: riderB.id, amount: 20, status: "SUCCEEDED" } }));

  const all = await withBypass((tx) => tx.payment.findMany());
  assert.equal(all.length, 2);
});

test("Payment: WITH CHECK blocks inserting a row owned by someone other than the current context", async () => {
  const { rider: owner, driver } = await createRiderAndDriver();
  const { rider: notOwner } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: owner.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });

  // Scoped to notOwner's context but the row being inserted claims to
  // belong to owner — the INSERT's WITH CHECK clause must reject this,
  // not just SELECTs.
  await assert.rejects(
    withUserContext(notOwner.id, (tx) =>
      tx.payment.create({ data: { tripId: trip.id, userId: owner.id, amount: 10, status: "SUCCEEDED" } }),
    ),
  );
});

test("Payout: withUserContext scopes strictly to the given driver", async () => {
  const { driverUser: driverUserA } = await createRiderAndDriver();
  const { driverUser: driverUserB } = await createRiderAndDriver();
  await withBypass((tx) => tx.payout.create({ data: { driverId: driverUserA.id, amount: 50, period: "2026-01" } }));
  await withBypass((tx) => tx.payout.create({ data: { driverId: driverUserB.id, amount: 75, period: "2026-01" } }));

  const asDriverA = await withUserContext(driverUserA.id, (tx) => tx.payout.findMany());
  assert.equal(asDriverA.length, 1);
  assert.equal(asDriverA[0].amount, 50);

  const asDriverB = await withUserContext(driverUserB.id, (tx) => tx.payout.findMany());
  assert.equal(asDriverB.length, 1);
  assert.equal(asDriverB[0].amount, 75);

  const noContext = await prisma.payout.findMany();
  assert.equal(noContext.length, 0);
});

test("DriverBankAccount: withUserContext scopes strictly to the given driver", async () => {
  const { driverUser: driverUserA } = await createRiderAndDriver();
  const { driverUser: driverUserB } = await createRiderAndDriver();
  await withBypass((tx) =>
    tx.driverBankAccount.create({
      data: { driverId: driverUserA.id, accountHolderName: "A", bankName: "Bank A", accountNumber: "1111", routingNumber: "000111" },
    }),
  );
  await withBypass((tx) =>
    tx.driverBankAccount.create({
      data: { driverId: driverUserB.id, accountHolderName: "B", bankName: "Bank B", accountNumber: "2222", routingNumber: "000222" },
    }),
  );

  const asDriverA = await withUserContext(driverUserA.id, (tx) => tx.driverBankAccount.findMany());
  assert.equal(asDriverA.length, 1);
  assert.equal(asDriverA[0].accountHolderName, "A");

  const asDriverB = await withUserContext(driverUserB.id, (tx) => tx.driverBankAccount.findMany());
  assert.equal(asDriverB.length, 1);
  assert.equal(asDriverB[0].accountHolderName, "B");

  const noContext = await prisma.driverBankAccount.findMany();
  assert.equal(noContext.length, 0);
});

test("Non-financial tables are unaffected by RLS — a plain query with no context still sees everything", async () => {
  const { rider } = await createRiderAndDriver();
  // User is not one of the three RLS-protected tables — a bare query must
  // work exactly as it always has, proving RLS wasn't accidentally turned
  // on somewhere it shouldn't be.
  const rows = await prisma.user.findMany({ where: { id: rider.id } });
  assert.equal(rows.length, 1);
});
