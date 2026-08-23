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

test("POST /api/trips offers an available ACTIVE driver, who accepts and becomes matched", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-6", role: "RIDER", firstName: "G", lastName: "H", email: "g@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-6", role: "DRIVER", firstName: "I", lastName: "J", email: "i@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE", online: true } });

  const token = mockAuthAs({ sub: "rider-sub-6", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  // A real offer went out — matching never auto-assigns. The trip itself
  // stays REQUESTED until the offered driver actually accepts.
  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);

  const offer = await prisma.tripOffer.findFirstOrThrow({ where: { tripId: res.body.id } });
  assert.equal(offer.driverId, driver.id);
  assert.equal(offer.status, "OFFERED");

  const acceptRes = await acceptOfferAsDriver("driver-sub-6");
  assert.equal(acceptRes.status, 200);
  assert.equal(acceptRes.body.status, "MATCHED");
  assert.equal(acceptRes.body.driverId, driver.id);
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
  // online: true — an ACTIVE-but-offline driver is not matching-eligible
  // (see matching.ts); every test using this helper expects a real driver
  // a rider could actually be matched to.
  return prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", online: true } });
}

/** The real two-step flow every "the driver gets matched" test now goes
 * through: matching only ever sends an offer (POST /trips), never an
 * automatic match — this fetches the given driver's pending offer and
 * accepts it, returning the PATCH .../accept response (the now-MATCHED
 * trip, or the error if there wasn't one / it lost a race). Switches the
 * mocked identity to this driver via mockAuthAs — only call this once the
 * test no longer needs a different identity's token to keep working. */
async function acceptOfferAsDriver(driverSub: string) {
  const token = mockAuthAs({ sub: driverSub, groups: ["Driver"] });
  const offerRes = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${token}`);
  assert.equal(offerRes.status, 200);
  assert.ok(offerRes.body, `expected driver ${driverSub} to have a pending offer`);
  return request(app).patch(`/api/trip-offers/${offerRes.body.id}/accept`).set("Authorization", `Bearer ${token}`);
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

test("KNOWN GAP (documented, not a code defect): with no active PricingRule, a wildly inflated client estimatedFare is still accepted", async () => {
  // This is the direct consequence of the back-compat fallback above: fare
  // validation at creation depends on an active PricingRule existing to
  // validate against. Operationally, staging/production must seed at least
  // one active PricingRule before accepting real trip traffic — see
  // FINAL_AWS_STAGING_READINESS.md. This test exists so that behavior
  // change here is deliberate, not silent.
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-fare-gap", role: "RIDER", firstName: "F", lastName: "G", email: "fare-gap@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-fare-gap", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 99999999 });

  assert.equal(res.status, 201);
  assert.equal(res.body.estimatedFare, 99999999);
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

test("POST /api/trips: two riders racing with exactly one ACTIVE driver free — the driver is offered only one trip", async () => {
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
  // Both trips stay REQUESTED at this point — matching never auto-assigns.
  assert.equal(resA.body.status, "REQUESTED");
  assert.equal(resB.body.status, "REQUESTED");

  // Exactly one of the two trips got a real offer to the one available
  // driver; the database-level partial unique index
  // (TripOffer_driverId_offered_unique) guarantees the driver can never
  // hold two simultaneous OFFERED offers, regardless of which request's
  // transaction happened to commit first.
  const offers = await prisma.tripOffer.findMany({ where: { driverId: driver.id } });
  assert.equal(offers.length, 1);
  assert.ok(offers[0].tripId === resA.body.id || offers[0].tripId === resB.body.id);
});

test("POST /api/trips does not match a driver already on an active courier request (Courier->Ride)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-courier-busy", role: "RIDER", firstName: "R", lastName: "C", email: "rc@example.com" },
  });
  const busyDriver = await createDriver("driver-sub-courier-busy");
  await prisma.driverAssignment.create({
    data: { driverId: busyDriver.id, assignmentType: "COURIER", assignmentId: "some-courier-id" },
  });

  const token = mockAuthAs({ sub: "rider-sub-courier-busy", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  // The only ACTIVE driver is busy on a courier request, so the trip stays
  // unmatched rather than double-booking that driver.
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
});

test("POST /api/trips does not match a driver whose rental booking is ACTIVE (Rental->Ride)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-rental-busy", role: "RIDER", firstName: "R", lastName: "R", email: "rr@example.com" },
  });
  const busyDriver = await createDriver("driver-sub-rental-busy");
  await prisma.driverAssignment.create({
    data: { driverId: busyDriver.id, assignmentType: "RENTAL", assignmentId: "some-booking-id" },
  });

  const token = mockAuthAs({ sub: "rider-sub-rental-busy", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
});

test("PATCH /api/trips/:id/status releases the driver's RIDE assignment on COMPLETED, freeing them for a courier request", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-release-1", role: "RIDER", firstName: "R", lastName: "L", email: "rl@example.com" },
  });
  const driver = await createDriver("driver-sub-release-1");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RIDE", assignmentId: trip.id },
  });

  const token = mockAuthAs({ sub: "driver-sub-release-1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 200);
  const assignment = await prisma.driverAssignment.findFirst({ where: { driverId: driver.id } });
  assert.equal(assignment?.status, "ENDED");
  assert.ok(assignment?.endedAt);
});

test("Concurrency: one ACTIVE driver — accepting a real ride offer and accepting a courier request race — exactly one wins", async () => {
  const sender = await prisma.user.create({
    data: { cognitoSub: "sender-sub-cr-race", role: "RIDER", firstName: "R", lastName: "S", email: "rs@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-cr-race", role: "RIDER", firstName: "R", lastName: "T", email: "rt@example.com" },
  });
  const driver = await createDriver("driver-sub-cr-race");
  const courierReq = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  // Requesting the ride (and the offer it generates) is not itself part of
  // the race — an unanswered offer no longer reserves the driver at all
  // (see TripOffer's own doc comment), so it can't conflict with anything
  // by merely existing. The real race, matching how every other
  // cross-domain concurrency test in this codebase is structured, is
  // between the two ACTUAL commitment actions: accepting the ride offer,
  // and accepting the courier request.
  const riderToken = mockAuthAs({ sub: "rider-sub-cr-race", groups: ["Rider"] });
  const tripRes = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 20 });
  assert.equal(tripRes.body.status, "REQUESTED");
  const offer = await prisma.tripOffer.findFirstOrThrow({ where: { tripId: tripRes.body.id } });
  assert.equal(offer.driverId, driver.id);

  const driverToken = mockAuthAs({ sub: "driver-sub-cr-race", groups: ["Driver"] });
  const [acceptOfferRes, acceptCourierRes] = await Promise.all([
    request(app).patch(`/api/trip-offers/${offer.id}/accept`).set("Authorization", `Bearer ${driverToken}`),
    request(app).patch(`/api/courier-requests/${courierReq.id}/accept`).set("Authorization", `Bearer ${driverToken}`),
  ]);

  const offerWon = acceptOfferRes.status === 200;
  const courierWon = acceptCourierRes.status === 200;
  // The single driver can win at most one of the two competing assignments
  // — never both, regardless of which request happened to commit first.
  assert.notEqual(offerWon, courierWon);

  const finalTrip = await prisma.trip.findUnique({ where: { id: tripRes.body.id } });
  assert.equal(finalTrip?.driverId, offerWon ? driver.id : null);
  const finalCourier = await prisma.courierRequest.findUnique({ where: { id: courierReq.id } });
  assert.equal(finalCourier?.driverId, courierWon ? driver.id : null);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1);
});

test("PATCH /api/trips/:id/status rejects jumping a REQUESTED trip straight to COMPLETED", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-illegal-1", role: "RIDER", firstName: "I", lastName: "L", email: "il1@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "REQUESTED" },
  });

  const token = mockAuthAs({ sub: "admin-sub-illegal-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 409);
  const unchanged = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(unchanged?.status, "REQUESTED");
});

test("PATCH /api/trips/:id/status rejects updating an already-terminal (CANCELLED) trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-illegal-2", role: "RIDER", firstName: "I", lastName: "L", email: "il2@example.com" },
  });
  const driver = await createDriver("driver-sub-illegal-2");
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      status: "CANCELLED",
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-illegal-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 12 });

  assert.equal(res.status, 409);
});

test("POST /api/trips: the matched driver's own vehicle is assigned to Trip.vehicleId", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-veh-1", role: "RIDER", firstName: "V", lastName: "1", email: "v1@example.com" },
  });
  const driver = await createDriver("driver-sub-veh-1");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Toyota", model: "Camry", colour: "Blue", plateNumber: "veh-1-plate", year: "2021" },
  });

  const token = mockAuthAs({ sub: "rider-sub-veh-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");

  const acceptRes = await acceptOfferAsDriver("driver-sub-veh-1");
  assert.equal(acceptRes.status, 200);
  assert.equal(acceptRes.body.status, "MATCHED");
  assert.equal(acceptRes.body.vehicleId, vehicle.id);
});

test("POST /api/trips: a driver with no vehicle on file still matches, with Trip.vehicleId left null (no invented vehicle)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-veh-2", role: "RIDER", firstName: "V", lastName: "2", email: "v2@example.com" },
  });
  await createDriver("driver-sub-veh-2");

  const token = mockAuthAs({ sub: "rider-sub-veh-2", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");

  const acceptRes = await acceptOfferAsDriver("driver-sub-veh-2");
  assert.equal(acceptRes.status, 200);
  assert.equal(acceptRes.body.status, "MATCHED");
  assert.equal(acceptRes.body.vehicleId, null);
});

test("POST /api/trips: a driver whose vehicle is on an active rental is excluded from matching entirely, not just for that vehicle", async () => {
  // Documents the actual, current design: DriverAssignment's exclusivity is
  // driver-level, not vehicle-level — reserveDriver()/isDriverAvailable()
  // key off the driver, so a driver with ANY active assignment (RIDE,
  // COURIER, or RENTAL, whichever vehicle it references) is excluded from
  // ride matching outright, even if they own a second, otherwise-free
  // vehicle. This is a deliberate reading of Part 2 as written ("a driver
  // must never simultaneously perform Ride + conflicting Rental") applied
  // at the driver level; see PRE_AWS_STRIPE_READINESS.md's Remaining Gaps
  // for why a stricter per-vehicle interpretation (letting the same driver
  // ride one car while renting out another) was not implemented here.
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-veh-3", role: "RIDER", firstName: "V", lastName: "3", email: "v3@example.com" },
  });
  const driver = await createDriver("driver-sub-veh-3");
  const busyVehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Honda", model: "Accord", colour: "Black", plateNumber: "veh-3-busy", year: "2020" },
  });
  await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Red", plateNumber: "veh-3-free", year: "2022" },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RENTAL", assignmentId: "some-booking-id", vehicleId: busyVehicle.id },
  });

  const token = mockAuthAs({ sub: "rider-sub-veh-3", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
});

test("POST /api/trips: a multi-vehicle driver with none busy gets their isPrimary vehicle assigned", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-veh-4", role: "RIDER", firstName: "V", lastName: "4", email: "v4@example.com" },
  });
  const driver = await createDriver("driver-sub-veh-4");
  await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Honda", model: "Accord", colour: "Black", plateNumber: "veh-4-secondary", year: "2020", isPrimary: false },
  });
  const primaryVehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Red", plateNumber: "veh-4-primary", year: "2022", isPrimary: true },
  });

  const token = mockAuthAs({ sub: "rider-sub-veh-4", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");

  const acceptRes = await acceptOfferAsDriver("driver-sub-veh-4");
  assert.equal(acceptRes.status, 200);
  assert.equal(acceptRes.body.status, "MATCHED");
  assert.equal(acceptRes.body.vehicleId, primaryVehicle.id);
});

test("GET /api/trips/:id 404s cleanly on a malformed/garbage id (not a 500)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-malformed-1", role: "RIDER", firstName: "M", lastName: "1", email: "m1@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-malformed-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/trips/' OR 1=1 --")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("PATCH /api/trips/:id/status 404s cleanly on a malformed/garbage id (not a 500)", async () => {
  const token = mockAuthAs({ sub: "admin-sub-malformed-1", groups: ["Admin"] });

  const res = await request(app)
    .patch("/api/trips/not-a-real-uuid/status")
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "MATCHED" });

  assert.equal(res.status, 404);
});

test("GET /api/trips/mine returns only the calling rider's own trips, most recent first", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-mine-1", role: "RIDER", firstName: "M", lastName: "1", email: "mine1@example.com" },
  });
  const otherRider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-mine-2", role: "RIDER", firstName: "M", lastName: "2", email: "mine2@example.com" },
  });
  await prisma.trip.create({
    data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  await prisma.trip.create({
    data: { riderId: otherRider.id, pickup: "X", destination: "Y", estimatedFare: 20 },
  });

  const token = mockAuthAs({ sub: "rider-sub-mine-1", groups: ["Rider"] });
  const res = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].riderId, rider.id);
});

test("GET /api/trips/mine rejects a caller who is neither Rider nor Driver", async () => {
  const token = mockAuthAs({ sub: "admin-sub-mine-1", groups: ["Admin"] });
  const res = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/trips/mine, called by a Driver, returns only that driver's own trips (driver_app's My Trips screen)", async () => {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-mine-2", role: "DRIVER", firstName: "M", lastName: "D", email: "mined@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const otherDriverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-mine-3", role: "DRIVER", firstName: "M", lastName: "D2", email: "mined2@example.com" },
  });
  const otherDriver = await prisma.driver.create({ data: { userId: otherDriverUser.id } });
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-mine-3", role: "RIDER", firstName: "M", lastName: "3", email: "mine3@example.com" },
  });
  await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "COMPLETED" },
  });
  await prisma.trip.create({
    data: { riderId: rider.id, driverId: otherDriver.id, pickup: "X", destination: "Y", estimatedFare: 20, status: "COMPLETED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-mine-2", groups: ["Driver"] });
  const res = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data[0].driverId, driver.id);
});

test("GET /api/trips/mine 404s for a Driver caller with no Driver profile yet", async () => {
  const token = mockAuthAs({ sub: "driver-sub-mine-4", groups: ["Driver"] });
  const res = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

// Regression: a double-tap on "Request Ride" (or a client retry) with no
// guard here used to create two independent Trip rows for the same rider,
// each independently run through matchDriverToTrip — the rider could end
// up matched to two different drivers for one intended request.
test("POST /api/trips rejects a second request while the rider already has an open trip", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-dup-1", role: "RIDER", firstName: "D", lastName: "1", email: "dup1@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-dup-1", groups: ["Rider"] });

  const first = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });
  assert.equal(first.status, 201);

  const second = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Mall", estimatedFare: 10 });
  assert.equal(second.status, 409);
  assert.equal(second.body.tripId, first.body.id);

  const trips = await prisma.trip.findMany({ where: { riderId: (await prisma.user.findUniqueOrThrow({ where: { cognitoSub: "rider-sub-dup-1" } })).id } });
  assert.equal(trips.length, 1);
});

test("POST /api/trips: two truly concurrent requests from the same rider — the database-level partial unique index rejects the loser, not just the application-level pre-check", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-dup-race", role: "RIDER", firstName: "D", lastName: "R", email: "duprace@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-dup-race", groups: ["Rider"] });

  // Both requests race the same read-then-write window the `openTrip`
  // application-level check can't fully close on its own — this is what
  // exercises Trip_riderId_open_unique (added in migration
  // 20260823083433_add_open_request_unique_indexes) rather than just the
  // sequential pre-check already covered by the test above.
  const [a, b] = await Promise.all([
    request(app)
      .post("/api/trips")
      .set("Authorization", `Bearer ${token}`)
      .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 }),
    request(app)
      .post("/api/trips")
      .set("Authorization", `Bearer ${token}`)
      .send({ pickup: "Home", destination: "Mall", estimatedFare: 10 }),
  ]);

  const statuses = [a.status, b.status].sort();
  assert.deepEqual(statuses, [201, 409]);

  const rider = await prisma.user.findUniqueOrThrow({ where: { cognitoSub: "rider-sub-dup-race" } });
  const trips = await prisma.trip.findMany({ where: { riderId: rider.id } });
  assert.equal(trips.length, 1, "exactly one Trip row must exist, even under a true race");
});

test("POST /api/trips allows a new request once the rider's previous trip reached a terminal status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-dup-2", role: "RIDER", firstName: "D", lastName: "2", email: "dup2@example.com" },
  });
  await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 10, status: "CANCELLED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-dup-2", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });
  assert.equal(res.status, 201);
});

// Regression: PATCH /trips/:id/cancel used to read the trip once, then
// unconditionally overwrite its status to CANCELLED and release a driver
// using that same stale, pre-transaction snapshot's driverId. A concurrent
// match (REQUESTED -> MATCHED, assigning a driver) between that read and
// the write used to get silently clobbered back to CANCELLED without ever
// releasing the newly-assigned driver, leaving their DriverAssignment
// orphaned ACTIVE forever. This test drives the route against a trip
// that's already MATCHED with an ACTIVE assignment (the state such a race
// would have left the DB in) and confirms cancel both succeeds and
// actually releases the driver.
test("PATCH /api/trips/:id/cancel releases the assigned driver's ACTIVE assignment, not just the trip status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-cancel-release", role: "RIDER", firstName: "C", lastName: "R", email: "cr@example.com" },
  });
  const driver = await createDriver("driver-sub-cancel-release");
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 10, status: "MATCHED" },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RIDE", assignmentId: trip.id },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-release", groups: ["Rider"] });
  const res = await request(app).patch(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");

  const assignment = await prisma.driverAssignment.findFirst({ where: { driverId: driver.id, status: "ACTIVE" } });
  assert.equal(assignment, null, "the driver's assignment must be released, not left orphaned ACTIVE");
});
