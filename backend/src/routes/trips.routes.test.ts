import assert from "node:assert/strict";
import { after, afterEach, beforeEach, mock, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { verifier } from "../middleware/auth";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
}

test("PATCH /api/trips/:id/status lets the trip's assigned Driver advance its status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const driver = await createDriver("driver-sub-2");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.ok(res.body.completedAt);
});

test("PATCH /api/trips/:id/status lets an Admin advance any trip's status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4b", role: "RIDER", firstName: "E", lastName: "F", email: "e2@example.com" },
  });
  const driver = await createDriver("driver-sub-2b");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
});

test("PATCH /api/trips/:id/status rejects a Driver who is not assigned to the trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4c", role: "RIDER", firstName: "E", lastName: "F", email: "e3@example.com" },
  });
  const assignedDriver = await createDriver("driver-sub-assigned");
  const otherDriver = await createDriver("driver-sub-other");
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: assignedDriver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      status: "MATCHED",
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-other", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 403);

  const untouched = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(untouched?.status, "MATCHED");
  void otherDriver;
});

test("PATCH /api/trips/:id/status rejects a Driver-group caller with no Driver record at all", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4d", role: "RIDER", firstName: "E", lastName: "F", email: "e4@example.com" },
  });
  const assignedDriver = await createDriver("driver-sub-assigned-2");
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: assignedDriver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      status: "MATCHED",
    },
  });

  // Valid Cognito token in the Driver group, but no Driver/User row was ever created for this sub.
  const token = mockAuthAs({ sub: "driver-sub-ghost", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 403);
});

test("PATCH /api/trips/:id/status rejects a Rider caller", async () => {
  const driver = await createDriver("driver-sub-2e");
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4e", role: "RIDER", firstName: "E", lastName: "F", email: "e5@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-4e", groups: ["Rider"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 403);
});

test("PATCH /api/trips/:id/status 404s for a nonexistent trip", async () => {
  await createDriver("driver-sub-2f");
  const token = mockAuthAs({ sub: "driver-sub-2f", groups: ["Driver"] });
  const res = await request(app)
    .patch("/api/trips/00000000-0000-0000-0000-000000000000/status")
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 404);
});

test("GET /api/trips (Admin monitor) rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const res = await request(app).get("/api/trips").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/trips/:id/cancel lets the owning rider cancel a REQUESTED trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-1", role: "RIDER", firstName: "C", lastName: "1", email: "cancel1@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "REQUESTED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-1", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");
});

test("PATCH /api/trips/:id/cancel lets the owning rider cancel a MATCHED trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-2", role: "RIDER", firstName: "C", lastName: "2", email: "cancel2@example.com" },
  });
  const driver = await createDriver("driver-sub-cancel-2");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-2", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");
});

test("PATCH /api/trips/:id/cancel rejects a different rider than the trip's owner", async () => {
  const owner = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-3", role: "RIDER", firstName: "C", lastName: "3", email: "cancel3@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-3b", role: "RIDER", firstName: "C", lastName: "3b", email: "cancel3b@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: owner.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "REQUESTED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-3b", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
  const untouched = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(untouched?.status, "REQUESTED");
});

test("PATCH /api/trips/:id/cancel rejects a Driver caller", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-4", role: "RIDER", firstName: "C", lastName: "4", email: "cancel4@example.com" },
  });
  const driver = await createDriver("driver-sub-cancel-4");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  // Even the assigned driver must not be able to cancel through the rider-only endpoint.
  const token = mockAuthAs({ sub: "driver-sub-cancel-4", groups: ["Driver"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});

test("PATCH /api/trips/:id/cancel rejects cancelling an IN_PROGRESS trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-5", role: "RIDER", firstName: "C", lastName: "5", email: "cancel5@example.com" },
  });
  const driver = await createDriver("driver-sub-cancel-5");
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      status: "IN_PROGRESS",
    },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-5", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  const untouched = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(untouched?.status, "IN_PROGRESS");
});

test("PATCH /api/trips/:id/cancel rejects cancelling an already-COMPLETED trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-6", role: "RIDER", firstName: "C", lastName: "6", email: "cancel6@example.com" },
  });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      finalFare: 12,
      status: "COMPLETED",
      completedAt: new Date(),
    },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-6", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
});

test("PATCH /api/trips/:id/cancel 404s for a nonexistent trip", async () => {
  const token = mockAuthAs({ sub: "rider-sub-cancel-7", groups: ["Rider"] });
  const res = await request(app)
    .patch("/api/trips/00000000-0000-0000-0000-000000000000/cancel")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("POST /api/trips computes estimatedFare server-side from distanceKm/durationMinutes, ignoring a client-supplied estimatedFare", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-1", role: "RIDER", firstName: "F", lastName: "1", email: "fare1@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", distanceKm: 10, durationMinutes: 20, estimatedFare: 999999 });

  assert.equal(res.status, 201);
  // 2 + 1*10 + 0.2*20 = 16, not the fabricated 999999 the client sent.
  assert.equal(res.body.estimatedFare, 16);
});

test("POST /api/trips applies the surge zone multiplier server-side when computing from distance/duration", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  await prisma.surgeZone.create({ data: { name: "Downtown", location: "City center", multiplier: 2 } });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-2", role: "RIDER", firstName: "F", lastName: "2", email: "fare2@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-2", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", distanceKm: 10, durationMinutes: 20, zone: "downtown" });

  assert.equal(res.status, 201);
  assert.equal(res.body.estimatedFare, 32);
});

test("POST /api/trips rejects a client estimatedFare materially below the active pricing rule's base fare", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 50, perKm: 1, perMinute: 0.2 } });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-3", role: "RIDER", firstName: "F", lastName: "3", email: "fare3@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-3", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 1 });

  assert.equal(res.status, 400);
});

test("POST /api/trips still accepts a plain client estimatedFare when no pricing rule is active (back-compat)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-4", role: "RIDER", firstName: "F", lastName: "4", email: "fare4@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-4", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.estimatedFare, 25.5);
});

test("POST /api/trips rejects missing estimatedFare when no distance/duration is given either", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-5", role: "RIDER", firstName: "F", lastName: "5", email: "fare5@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-5", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport" });

  assert.equal(res.status, 400);
});

test("PATCH /api/trips/:id/status rejects a finalFare far above the trip's estimatedFare", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-6", role: "RIDER", firstName: "F", lastName: "6", email: "fare6@example.com" },
  });
  const driver = await createDriver("driver-sub-fare-6");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 20, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-fare-6", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 500 }); // way more than 2x the $20 estimate

  assert.equal(res.status, 400);
  const untouched = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(untouched?.status, "MATCHED");
});

test("PATCH /api/trips/:id/status rejects a finalFare far below the trip's estimatedFare", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-7", role: "RIDER", firstName: "F", lastName: "7", email: "fare7@example.com" },
  });
  const driver = await createDriver("driver-sub-fare-7");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 20, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-fare-7", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 0.5 }); // way less than 0.5x the $20 estimate

  assert.equal(res.status, 400);
});

test("PATCH /api/trips/:id/status accepts a finalFare within the allowed variance band", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-8", role: "RIDER", firstName: "F", lastName: "8", email: "fare8@example.com" },
  });
  const driver = await createDriver("driver-sub-fare-8");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 20, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-fare-8", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 28 }); // 1.4x the $20 estimate, within 0.5x-2x

  assert.equal(res.status, 200);
  assert.equal(res.body.finalFare, 28);
});

test("POST /api/trips: two riders racing with exactly one ACTIVE driver free — the driver is matched to only one trip", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-race-a", role: "RIDER", firstName: "R", lastName: "A", email: "race-a@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-race-b", role: "RIDER", firstName: "R", lastName: "B", email: "race-b@example.com" },
  });
  const driver = await createDriver("driver-sub-race-only");

  // Two riders need simultaneously-valid tokens, which mockAuthAs() (one
  // active mock at a time) doesn't support — mock the verifier directly.
  const tokenA = "mock.rider-sub-race-a";
  const tokenB = "mock.rider-sub-race-b";
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate === tokenA) return { sub: "rider-sub-race-a", "cognito:groups": ["Rider"] } as never;
    if (candidate === tokenB) return { sub: "rider-sub-race-b", "cognito:groups": ["Rider"] } as never;
    throw new Error("invalid token");
  });

  const [resA, resB] = await Promise.all([
    request(app)
      .post("/api/trips")
      .set("Authorization", `Bearer ${tokenA}`)
      .send({ pickup: "Home A", destination: "Work A", estimatedFare: 20 }),
    request(app)
      .post("/api/trips")
      .set("Authorization", `Bearer ${tokenB}`)
      .send({ pickup: "Home B", destination: "Work B", estimatedFare: 20 }),
  ]);

  assert.equal(resA.status, 201);
  assert.equal(resB.status, 201);
  const matchedStatuses = [resA.body.status, resB.body.status].sort();
  // Exactly one trip is MATCHED to the one available driver; the other is
  // left REQUESTED — never both MATCHED to the same driver.
  assert.deepEqual(matchedStatuses, ["MATCHED", "REQUESTED"]);

  const matchedTrips = await prisma.trip.findMany({ where: { driverId: driver.id } });
  assert.equal(matchedTrips.length, 1);
});
