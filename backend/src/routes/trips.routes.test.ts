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

test("PATCH /api/trips/:id/status lets a Driver or Admin advance trip status, computing finalFare server-side", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1.5, perMinute: 0.25, active: true } });

  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-2", role: "DRIVER", firstName: "O", lastName: "P", email: "o@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    // IN_PROGRESS, not MATCHED — COMPLETED is only reachable from
    // IN_PROGRESS or DISPUTED per VALID_TRIP_TRANSITIONS; MATCHED must go
    // through IN_PROGRESS first.
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", distanceKm: 10, durationMinutes: 20 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.ok(res.body.completedAt);
  // 2 + 1.5*10 + 0.25*20 = 22 — driven entirely by the active PricingRule
  // and the driver-reported distance/duration, not by anything the driver
  // could set directly.
  assert.equal(res.body.finalFare, 22);
  assert.equal(res.body.distanceKm, 10);
  assert.equal(res.body.durationMinutes, 20);
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
  // IN_PROGRESS deliberately, not COMPLETED — this isolates the
  // authorization check under test from fare-calculation entirely (no
  // distanceKm/durationMinutes needed for a non-COMPLETED transition), so a
  // schema-validation 400 can't masquerade as the 403 this test expects.
  const otherRes = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${otherToken}`)
    .send({ status: "IN_PROGRESS" });
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

// Fare-integrity: a driver (or anyone) cannot set the Stripe-charged amount
// directly — it's always calculateFinalFare's output, never a value out of
// the request body. These prove that at the HTTP boundary, not just at the
// service-function boundary already covered by services/fare.test.ts.
test("PATCH /api/trips/:id/status: a request body finalFare is ignored — the charge is always server-computed", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 0, perKm: 1, perMinute: 0, active: true } });

  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-10", role: "RIDER", firstName: "A", lastName: "A", email: "fare-a@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-10", role: "DRIVER", firstName: "B", lastName: "B", email: "fare-b@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 5, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-sub-10", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    // A driver trying to charge $10,000 for what the rate card says is a
    // 3km ride — this used to work when finalFare was accepted directly.
    .send({ status: "COMPLETED", distanceKm: 3, durationMinutes: 5, finalFare: 10000 });

  assert.equal(res.status, 200);
  // baseFare 0 + perKm 1 * 3km = 3, not 10000 — the extra field is not
  // just capped or clamped, it's not read from at all.
  assert.equal(res.body.finalFare, 3);
});

test("PATCH /api/trips/:id/status rejects completing a trip with no active pricing rule, rather than defaulting a fare", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-11", role: "RIDER", firstName: "C", lastName: "C", email: "fare-c@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-11", role: "DRIVER", firstName: "D", lastName: "D", email: "fare-d@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 5, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-sub-11", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", distanceKm: 3, durationMinutes: 5 });

  assert.equal(res.status, 409);
  const unchanged = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(unchanged?.status, "IN_PROGRESS");
  assert.equal(unchanged?.finalFare, null);
});

test("PATCH /api/trips/:id/status rejects completing a trip with no distanceKm/durationMinutes", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-12", role: "RIDER", firstName: "E", lastName: "E", email: "fare-e@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-12", role: "DRIVER", firstName: "F", lastName: "F", email: "fare-f@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 5, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-12", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED" });

  assert.equal(res.status, 400);
});

test("PATCH /api/trips/:id/status: two concurrent COMPLETED requests for the same trip only apply once", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 0, perKm: 1, perMinute: 0, active: true } });

  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-13", role: "RIDER", firstName: "G", lastName: "G", email: "fare-g@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-13", role: "DRIVER", firstName: "H", lastName: "H", email: "fare-h@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 5, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-sub-13", groups: ["Driver"] });
  const send = () =>
    request(app)
      .patch(`/api/trips/${trip.id}/status`)
      .set("Authorization", `Bearer ${token}`)
      .send({ status: "COMPLETED", distanceKm: 4, durationMinutes: 5 });

  const [first, second] = await Promise.all([send(), send()]);
  const statuses = [first.status, second.status];
  // Exactly one must succeed. The loser can come back either way depending
  // on how the two requests actually interleaved: 409 if it read the same
  // stale "IN_PROGRESS" as the winner and then lost the atomic conditional
  // update (updateMany's WHERE no longer matches), or 400 if it didn't even
  // get that far — its own findUnique already saw the winner's committed
  // "COMPLETED" and correctly refused an invalid COMPLETED→COMPLETED
  // transition. Both prove the same thing: the second request never
  // applied the completion a second time. What must never happen is [200, 200].
  assert.equal(statuses.filter((s) => s === 200).length, 1);
  assert.ok(statuses.includes(409) || statuses.includes(400));

  const updatedDriver = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(updatedDriver?.totalTrips, 1);
});
