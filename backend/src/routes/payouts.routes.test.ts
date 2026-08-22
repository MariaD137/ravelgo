import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await prisma.payout.deleteMany();
  await prisma.driverBankAccount.deleteMany();
  await resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.payout.deleteMany();
  await prisma.driverBankAccount.deleteMany();
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

const bankAccountPayload = {
  accountHolderName: "Jane Driver",
  bankName: "First Bank",
  accountNumber: "12345678",
  routingNumber: "123456789",
};

test("POST /api/payouts/bank-account lets the calling driver register their own bank account", async () => {
  const user = await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);

  assert.equal(res.status, 201);
  assert.equal(res.body.driverId, user.id);
  assert.equal(res.body.accountHolderName, "Jane Driver");

  const stored = await prisma.driverBankAccount.findUnique({ where: { driverId: user.id } });
  assert.ok(stored);
});

test("GET /api/payouts/bank-account returns the calling driver's own bank account", async () => {
  const user = await createDriver("driver-sub-2");
  await prisma.driverBankAccount.create({ data: { driverId: user.id, ...bankAccountPayload } });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.driverId, user.id);
});

test("GET /api/payouts/history returns only the calling driver's own payouts", async () => {
  const driverA = await createDriver("driver-sub-3");
  const driverB = await createDriver("driver-sub-4");
  await prisma.payout.create({ data: { driverId: driverA.id, amount: 100, period: "2026-07", status: "PENDING" } });
  await prisma.payout.create({ data: { driverId: driverB.id, amount: 200, period: "2026-07", status: "PENDING" } });

  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].driverId, driverA.id);
  assert.equal(res.body.data[0].amount, 100);
});

test("GET /api/payouts/:id lets the calling driver retrieve their own payout", async () => {
  const driver = await createDriver("driver-sub-5");
  const payout = await prisma.payout.create({
    data: { driverId: driver.id, amount: 150, period: "2026-07", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "driver-sub-5", groups: ["Driver"] });
  const res = await request(app).get(`/api/payouts/${payout.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.id, payout.id);
});

test("GET /api/payouts/:id 404s when the payout belongs to a different driver", async () => {
  const driverA = await createDriver("driver-sub-6");
  const driverB = await createDriver("driver-sub-7");
  const payout = await prisma.payout.create({
    data: { driverId: driverB.id, amount: 300, period: "2026-07", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });
  const res = await request(app).get(`/api/payouts/${payout.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
  void driverA;
});

test("Payout endpoints reject a caller with a valid token but no matching User row", async () => {
  const token = mockAuthAs({ sub: "cognito-sub-with-no-user-row", groups: ["Driver"] });

  const bankAccountRes = await request(app)
    .get("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(bankAccountRes.status, 404);

  const historyRes = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${token}`);
  assert.equal(historyRes.status, 404);
});

test("Payout endpoints 404 for a User row that exists but has no Driver relationship (wrong role)", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "rider-sub-in-driver-group",
      role: "RIDER",
      firstName: "R",
      lastName: "I",
      email: "rider-sub-in-driver-group@example.com",
    },
  });
  const token = mockAuthAs({ sub: "rider-sub-in-driver-group", groups: ["Driver"] });

  const res = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("POST /api/payouts/bank-account requires auth", async () => {
  const res = await request(app).post("/api/payouts/bank-account").send(bankAccountPayload);
  assert.equal(res.status, 401);
});

test("POST /api/payouts/bank-account rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);
  assert.equal(res.status, 403);
});

// Regression: calculatePayoutForPeriod used to query Trip/DriverSubscription
// by the User.id it was given directly, but Trip.driverId and
// DriverSubscription.driverId are foreign keys to Driver.id — a different
// row entirely (Payout.driverId/DriverBankAccount.driverId are the ones
// that are actually User.id; see payouts.routes.ts's own comment on that
// naming). Passing User.id straight into those two queries meant they never
// matched any row, so grossAmount silently computed as 0 regardless of how
// many completed, paid trips the driver actually had — a payout that
// should have had real money in it, calculated and created as $0.
test("POST /api/payouts/calculate reflects a driver's actual completed, paid trips (not always 0)", async () => {
  const driverUser = await createDriver("driver-sub-calc-1");
  const driver = await prisma.driver.findUniqueOrThrow({ where: { userId: driverUser.id } });
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-calc-1", role: "RIDER", firstName: "R", lastName: "1", email: "rcalc1@example.com" },
  });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 100,
      finalFare: 100,
      status: "COMPLETED",
      completedAt: new Date("2026-06-15T00:00:00.000Z"),
    },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 100, status: "SUCCEEDED", paidAt: new Date("2026-06-15T00:10:00.000Z") },
  });

  const adminToken = mockAuthAs({ sub: "admin-sub-calc-1", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/payouts/calculate")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ driverId: driverUser.id, period: "2026-06" });

  assert.equal(res.status, 200);
  assert.equal(res.body.tripsIncluded, 1);
  assert.equal(res.body.grossAmount, 100);
  assert.equal(res.body.platformFee, 20);
  assert.equal(res.body.netAmount, 80);
});

test("POST /api/payouts/create (calculated branch) persists the same nonzero amount and masks the driver's bank account numbers", async () => {
  const driverUser = await createDriver("driver-sub-calc-2");
  const driver = await prisma.driver.findUniqueOrThrow({ where: { userId: driverUser.id } });
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-calc-2", role: "RIDER", firstName: "R", lastName: "2", email: "rcalc2@example.com" },
  });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 200,
      finalFare: 200,
      status: "COMPLETED",
      completedAt: new Date("2026-07-01T00:00:00.000Z"),
    },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 200, status: "SUCCEEDED", paidAt: new Date("2026-07-01T00:10:00.000Z") },
  });
  await prisma.driverBankAccount.create({ data: { driverId: driverUser.id, ...bankAccountPayload } });

  const adminToken = mockAuthAs({ sub: "admin-sub-calc-2", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/payouts/create")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ driverId: driverUser.id, period: "2026-07" });

  assert.equal(res.status, 201);
  // netAmount = 200 gross - 20% platform fee = 160.
  assert.equal(res.body.amount, 160);

  const stored = await prisma.payout.findUniqueOrThrow({ where: { id: res.body.id } });
  assert.equal(stored.amount, 160);

  // The full account/routing number has no reason to travel to an Admin's
  // browser just to create a payout record.
  assert.equal(res.body.driver.bankAccount.accountNumber, "****5678");
  assert.equal(res.body.driver.bankAccount.routingNumber, "*****6789");
  assert.notEqual(res.body.driver.bankAccount.accountNumber, bankAccountPayload.accountNumber);
});
