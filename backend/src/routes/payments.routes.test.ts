import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, mockPaymentIntentCreate, mockPaymentIntentRetrieve, restoreAuth, resetDb } from "../test/helpers";
import { withBypass } from "../lib/rls";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function createRiderAndDriver() {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-1", role: "DRIVER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  return { rider, driver };
}

test("POST /api/trips/:id/charge refuses to charge a trip that isn't COMPLETED", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({});

  assert.equal(res.status, 409);
});

test("POST /api/trips/:id/charge (CARD) creates a Stripe PaymentIntent, PENDING until the webhook confirms it, and rejects a second charge", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 10,
      finalFare: 14.5,
      status: "COMPLETED",
    },
  });

  const intentId = mockPaymentIntentCreate();
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const first = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });

  assert.equal(first.status, 201);
  assert.equal(first.body.amount, 14.5);
  assert.equal(first.body.status, "PENDING");
  assert.equal(first.body.providerReference, intentId);
  assert.ok(first.body.clientSecret);

  const second = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });
  assert.equal(second.status, 409);
});

test("GET /api/trips/:id/payment-secret returns the clientSecret for the rider's own pending CARD payment", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 14.5, status: "COMPLETED" },
  });

  const intentId = mockPaymentIntentCreate();
  const driverToken = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const charge = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ method: "CARD" });
  assert.equal(charge.status, 201);

  restoreAuth();
  mockPaymentIntentRetrieve(intentId);
  const riderToken = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .get(`/api/trips/${trip.id}/payment-secret`)
    .set("Authorization", `Bearer ${riderToken}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.paymentId, charge.body.id);
  assert.equal(res.body.clientSecret, `${intentId}_secret_test`);
});

test("GET /api/trips/:id/payment-secret 403s for a rider who isn't party to the trip", async () => {
  const { rider, driver } = await createRiderAndDriver();
  await prisma.user.create({
    data: { cognitoSub: "stranger-sub", role: "RIDER", firstName: "S", lastName: "T", email: "s@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 14.5, status: "COMPLETED" },
  });

  const intentId = mockPaymentIntentCreate();
  const driverToken = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  await request(app).post(`/api/trips/${trip.id}/charge`).set("Authorization", `Bearer ${driverToken}`).send({ method: "CARD" });

  restoreAuth();
  mockPaymentIntentRetrieve(intentId);
  const strangerToken = mockAuthAs({ sub: "stranger-sub", groups: ["Rider"] });
  const res = await request(app)
    .get(`/api/trips/${trip.id}/payment-secret`)
    .set("Authorization", `Bearer ${strangerToken}`);

  assert.equal(res.status, 403);
});

test("GET /api/trips/:id/payment-secret 404s when no payment has been created yet", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 14.5, status: "COMPLETED" },
  });

  const riderToken = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .get(`/api/trips/${trip.id}/payment-secret`)
    .set("Authorization", `Bearer ${riderToken}`);

  assert.equal(res.status, 404);
});

test("GET /api/trips/:id/payment-secret 409s once the payment is no longer pending", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 14.5, status: "COMPLETED" },
  });
  await withBypass((tx) =>
    tx.payment.create({
      data: { tripId: trip.id, userId: rider.id, amount: 14.5, method: "CARD", status: "SUCCEEDED", providerReference: "pi_done", paidAt: new Date() },
    }),
  );

  const riderToken = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .get(`/api/trips/${trip.id}/payment-secret`)
    .set("Authorization", `Bearer ${riderToken}`);

  assert.equal(res.status, 409);
});

test("POST /api/trips/:id/charge (CASH) settles immediately, no Stripe call involved", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 10,
      finalFare: 14.5,
      status: "COMPLETED",
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CASH" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "SUCCEEDED");
  assert.ok(res.body.paidAt);
});

test("POST /api/trips/:id/charge rejects a driver who wasn't on the trip", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 10,
      finalFare: 14.5,
      status: "COMPLETED",
    },
  });

  const token = mockAuthAs({ sub: "some-other-driver", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({});

  assert.equal(res.status, 403);
});

test("GET /api/payments/mine only returns the caller's own payments", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 10, status: "COMPLETED" },
  });
  await withBypass((tx) =>
    tx.payment.create({ data: { tripId: trip.id, userId: rider.id, amount: 10, status: "SUCCEEDED", paidAt: new Date() } }),
  );

  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app).get("/api/payments/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.total, 1);
});

test("GET /api/payments rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const res = await request(app).get("/api/payments").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/payments/:id/receipt is visible to the paying rider, denied to a stranger", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "Home", destination: "Work", estimatedFare: 10, finalFare: 10, status: "COMPLETED" },
  });
  const payment = await withBypass((tx) =>
    tx.payment.create({
      data: { tripId: trip.id, userId: rider.id, amount: 10, status: "SUCCEEDED", paidAt: new Date() },
    }),
  );

  const ownerToken = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const ownerRes = await request(app).get(`/api/payments/${payment.id}/receipt`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownerRes.status, 200);
  assert.equal(ownerRes.body.pickup, "Home");
  assert.equal(ownerRes.body.amount, 10);

  // A real user, just not this payment's owner — exercises the RLS path
  // itself, not just the "no such user profile" 404 branch.
  await prisma.user.create({
    data: { cognitoSub: "stranger-sub", role: "RIDER", firstName: "S", lastName: "T", email: "s@example.com" },
  });
  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "stranger-sub", groups: ["Rider"] });
  const strangerRes = await request(app).get(`/api/payments/${payment.id}/receipt`).set("Authorization", `Bearer ${strangerToken}`);
  // Row-level security scopes this query to the caller's own payments, so a
  // payment that exists but isn't theirs is indistinguishable from one that
  // doesn't exist — 404, not 403, so existence isn't leaked to a stranger.
  assert.equal(strangerRes.status, 404);
});
