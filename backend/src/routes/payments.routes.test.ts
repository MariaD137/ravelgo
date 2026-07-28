import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

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

test("POST /api/trips/:id/charge creates a Payment for a completed trip and rejects a second charge", async () => {
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
  const first = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });

  assert.equal(first.status, 201);
  assert.equal(first.body.amount, 14.5);
  assert.equal(first.body.status, "SUCCEEDED");

  const second = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });
  assert.equal(second.status, 409);
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
  await prisma.payment.create({ data: { tripId: trip.id, userId: rider.id, amount: 10, status: "SUCCEEDED", paidAt: new Date() } });

  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app).get("/api/payments/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
});

test("GET /api/payments rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const res = await request(app).get("/api/payments").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
