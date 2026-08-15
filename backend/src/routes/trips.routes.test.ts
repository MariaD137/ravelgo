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

test("POST /api/trips lets a Rider request a trip", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
});

test("POST /api/trips auto-matches an available ACTIVE driver", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-6", role: "RIDER", firstName: "G", lastName: "H", email: "g@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-6", role: "DRIVER", firstName: "I", lastName: "J", email: "i@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });

  const token = mockAuthAs({ sub: "rider-sub-6", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "MATCHED");
  assert.equal(res.body.driverId, driver.id);
});

test("POST /api/trips leaves a trip REQUESTED when no ACTIVE driver is free", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-7", role: "RIDER", firstName: "K", lastName: "L", email: "k@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-7", role: "DRIVER", firstName: "M", lastName: "N", email: "m@example.com" },
  });
  await prisma.driver.create({ data: { userId: driverUser.id, status: "PENDING_REVIEW" } });

  const token = mockAuthAs({ sub: "rider-sub-7", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
});

test("POST /api/trips rejects a Driver caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });
  assert.equal(res.status, 403);
});

test("GET /api/trips/:id allows the rider who owns it, denies a stranger", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-2", role: "RIDER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12 },
  });

  const ownerToken = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const ownerRes = await request(app).get(`/api/trips/${trip.id}`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownerRes.status, 200);

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });
  const strangerRes = await request(app).get(`/api/trips/${trip.id}`).set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 403);
});

test("PATCH /api/trips/:id/status lets a Driver or Admin advance trip status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-2", role: "DRIVER", firstName: "O", lastName: "P", email: "o@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 14 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.ok(res.body.completedAt);
});

test("PATCH /api/trips/:id/status denies a Driver who isn't assigned to the trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-8", role: "RIDER", firstName: "Q", lastName: "R", email: "q@example.com" },
  });
  const assignedDriverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-8", role: "DRIVER", firstName: "S", lastName: "T", email: "s@example.com" },
  });
  const assignedDriver = await prisma.driver.create({ data: { userId: assignedDriverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: assignedDriver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  await prisma.user.create({
    data: { cognitoSub: "driver-sub-9", role: "DRIVER", firstName: "U", lastName: "V", email: "u@example.com" },
  });
  const otherToken = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });
  const otherRes = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${otherToken}`)
    .send({ status: "COMPLETED", finalFare: 14 });
  assert.equal(otherRes.status, 403);

  restoreAuth();
  const unassignedTrip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "REQUESTED" },
  });
  const noDriverToken = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });
  const noDriverRes = await request(app)
    .patch(`/api/trips/${unassignedTrip.id}/status`)
    .set("Authorization", `Bearer ${noDriverToken}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(noDriverRes.status, 403);
});

test("GET /api/trips (Admin monitor) rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const res = await request(app).get("/api/trips").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
