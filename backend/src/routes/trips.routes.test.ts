import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { locatedAt, mockAuthAs, restoreAuth, resetDb } from "../test/helpers";
import { estimateDurationMinutes, haversineKm } from "../lib/geo";
import { computeFare } from "../services/pricing";
import { getRiderLocation, resetRealtimeState } from "../realtime/hub";

beforeEach(async () => {
  resetRealtimeState();
  await resetDb();
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
  // Fare is computed server-side against the active rule: 2 + 1*km + 0.2*min.
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
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

// Coordinates are the authoritative fare input now — the server computes the
// distance (and thus the fare); the client can no longer assert distanceKm.
const RULE = { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 };
const PICKUP = { lat: 6.5244, lng: 3.3792 }; // Lagos
const DROPOFF = { lat: 6.4478, lng: 3.4723 };
const tripInput = {
  pickup: "Home",
  destination: "Airport",
  pickupLat: PICKUP.lat,
  pickupLng: PICKUP.lng,
  dropoffLat: DROPOFF.lat,
  dropoffLng: DROPOFF.lng,
};
// Recompute the expected fare exactly as the server would, from the same geo
// + pricing helpers — proves the stored fare matches the authoritative figure
// for these coordinates without hardcoding a magic number.
const _dist = haversineKm(PICKUP, DROPOFF);
const EXPECTED_FARE = computeFare(RULE, _dist, estimateDurationMinutes(_dist)).estimatedFare;

test("POST /api/trips lets a Rider request a trip, with a server-computed fare", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.estimatedFare, EXPECTED_FARE);
});

test("POST /api/trips ignores a client-supplied estimatedFare and uses the server figure", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-cheat", role: "RIDER", firstName: "A", lastName: "B", email: "cheat@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-cheat", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    // The classic attack: try to assert a 1-unit fare.
    .send({ ...tripInput, estimatedFare: 1 });

  assert.equal(res.status, 201);
  // Server ignored the injected value entirely.
  assert.equal(res.body.estimatedFare, EXPECTED_FARE);
});

test("POST /api/trips 409s when no pricing rule is configured", async () => {
  await prisma.pricingRule.deleteMany();
  await prisma.user.create({
    data: { cognitoSub: "rider-noprice", role: "RIDER", firstName: "A", lastName: "B", email: "np@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-noprice", groups: ["Rider"] });

  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);
  assert.equal(res.status, 409);
});

test("POST /api/trips rejects missing, malformed, and negative trip inputs", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-bad", role: "RIDER", firstName: "A", lastName: "B", email: "bad@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-bad", groups: ["Rider"] });

  const bad: Array<Record<string, unknown>> = [
    { pickup: "H", destination: "A" }, // missing coordinates
    { ...tripInput, pickupLat: "north" }, // malformed
    { ...tripInput, dropoffLat: 200 }, // out of range
    { ...tripInput, pickupLng: -999 }, // out of range
  ];
  for (const body of bad) {
    const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(body);
    assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(body)}`);
  }
});

test("POST /api/trips offers an available ACTIVE driver, but does not yet MATCH them", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-6", role: "RIDER", firstName: "G", lastName: "H", email: "g@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-6", role: "DRIVER", firstName: "I", lastName: "J", email: "i@example.com" },
  });
  const driver = await prisma.driver.create({
    data: { userId: driverUser.id, status: "ACTIVE", isOnline: true, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });

  const token = mockAuthAs({ sub: "rider-sub-6", groups: ["Rider"] });
  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);

  // P0 special requirement: matching offers a trip, it doesn't fake an
  // acceptance the driver hasn't given yet.
  assert.equal(res.status, 201);
  assert.equal(res.body.status, "OFFERED");
  assert.equal(res.body.driverId, driver.id);
});

test("POST /api/trips/:id/accept lets the offered driver actually accept, moving the trip to MATCHED", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-accept-1", role: "RIDER", firstName: "G", lastName: "H", email: "accept1r@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-accept-1", role: "DRIVER", firstName: "I", lastName: "J", email: "accept1d@example.com" },
  });
  await prisma.driver.create({
    data: { userId: driverUser.id, status: "ACTIVE", isOnline: true, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });

  const riderToken = mockAuthAs({ sub: "rider-accept-1", groups: ["Rider"] });
  const created = await request(app).post("/api/trips").set("Authorization", `Bearer ${riderToken}`).send(tripInput);
  assert.equal(created.body.status, "OFFERED");

  const driverToken = mockAuthAs({ sub: "driver-accept-1", groups: ["Driver"] });
  const accepted = await request(app)
    .post(`/api/trips/${created.body.id}/accept`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send();

  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.status, "MATCHED");
});

test("POST /api/trips/:id/decline releases the offer and re-offers it to the next eligible driver, never cancelling the rider's trip", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-decline-1", role: "RIDER", firstName: "G", lastName: "H", email: "decline1r@example.com" },
  });
  const decliningUser = await prisma.user.create({
    data: { cognitoSub: "driver-decline-1", role: "DRIVER", firstName: "I", lastName: "J", email: "decline1d@example.com" },
  });
  const decliningDriver = await prisma.driver.create({
    data: { userId: decliningUser.id, status: "ACTIVE", isOnline: true, rating: 5.0, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });
  const secondUser = await prisma.user.create({
    data: { cognitoSub: "driver-decline-2", role: "DRIVER", firstName: "K", lastName: "L", email: "decline2d@example.com" },
  });
  const secondDriver = await prisma.driver.create({
    data: { userId: secondUser.id, status: "ACTIVE", isOnline: true, rating: 4.0, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });

  const riderToken = mockAuthAs({ sub: "rider-decline-1", groups: ["Rider"] });
  const created = await request(app).post("/api/trips").set("Authorization", `Bearer ${riderToken}`).send(tripInput);
  // Highest-rated driver is offered first.
  assert.equal(created.body.driverId, decliningDriver.id);

  const decliningToken = mockAuthAs({ sub: "driver-decline-1", groups: ["Driver"] });
  const declined = await request(app)
    .post(`/api/trips/${created.body.id}/decline`)
    .set("Authorization", `Bearer ${decliningToken}`)
    .send();
  assert.equal(declined.status, 204);

  const after = await prisma.trip.findUniqueOrThrow({ where: { id: created.body.id } });
  // Never cancelled — re-offered to the next eligible driver instead.
  assert.equal(after.status, "OFFERED");
  assert.equal(after.driverId, secondDriver.id);
  assert.ok(after.declinedDriverIds.includes(decliningDriver.id));

  // The declining driver is never re-offered the same trip again.
  const secondDeclineAttempt = await request(app)
    .post(`/api/trips/${created.body.id}/decline`)
    .set("Authorization", `Bearer ${decliningToken}`)
    .send();
  assert.equal(secondDeclineAttempt.status, 409);
});

test("POST /api/trips/:id/accept: two concurrent accepts for the same offer — only one wins", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-race-1", role: "RIDER", firstName: "G", lastName: "H", email: "race1r@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-race-1", role: "DRIVER", firstName: "I", lastName: "J", email: "race1d@example.com" },
  });
  await prisma.driver.create({
    data: { userId: driverUser.id, status: "ACTIVE", isOnline: true, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });

  const riderToken = mockAuthAs({ sub: "rider-race-1", groups: ["Rider"] });
  const created = await request(app).post("/api/trips").set("Authorization", `Bearer ${riderToken}`).send(tripInput);

  const driverToken = mockAuthAs({ sub: "driver-race-1", groups: ["Driver"] });
  const [first, second] = await Promise.all([
    request(app).post(`/api/trips/${created.body.id}/accept`).set("Authorization", `Bearer ${driverToken}`).send(),
    request(app).post(`/api/trips/${created.body.id}/accept`).set("Authorization", `Bearer ${driverToken}`).send(),
  ]);
  const statuses = [first.status, second.status].sort();
  // Exactly one 200 (the winner) and one 409 (the loser) — never two 200s.
  assert.deepEqual(statuses, [200, 409]);
});

test("A driver cannot accept a ride while already carrying an active delivery", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-conflict-1", role: "RIDER", firstName: "G", lastName: "H", email: "conflict1r@example.com" },
  });
  const senderUser = await prisma.user.create({
    data: { cognitoSub: "sender-conflict-1", role: "RIDER", firstName: "S", lastName: "L", email: "conflict1s@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-conflict-1", role: "DRIVER", firstName: "I", lastName: "J", email: "conflict1d@example.com" },
  });
  const driver = await prisma.driver.create({
    data: { userId: driverUser.id, status: "ACTIVE", isOnline: true, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });
  // This driver already has an active (MATCHED) delivery.
  await prisma.courierRequest.create({
    data: {
      senderId: senderUser.id,
      driverId: driver.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "box",
      recipientName: "R",
      recipientPhone: "123",
      estimatedFare: 1000,
      status: "MATCHED",
    },
  });

  const riderToken = mockAuthAs({ sub: "rider-conflict-1", groups: ["Rider"] });
  const created = await request(app).post("/api/trips").set("Authorization", `Bearer ${riderToken}`).send(tripInput);
  // Matching itself must skip this driver — nobody else is eligible, so the
  // trip stays REQUESTED rather than being offered to a conflicted driver.
  assert.equal(created.body.status, "REQUESTED");
  assert.equal(created.body.driverId, null);

  // Defense in depth: even if somehow offered, accept must still reject it.
  await prisma.trip.update({
    where: { id: created.body.id },
    data: { status: "OFFERED", driverId: driver.id, offerExpiresAt: new Date(Date.now() + 60_000) },
  });
  const driverToken = mockAuthAs({ sub: "driver-conflict-1", groups: ["Driver"] });
  const accepted = await request(app)
    .post(`/api/trips/${created.body.id}/accept`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send();
  assert.equal(accepted.status, 409);
});

test("POST /api/trips leaves a trip REQUESTED when the only ACTIVE driver is offline", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-offline", role: "RIDER", firstName: "G", lastName: "H", email: "goff@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-offline", role: "DRIVER", firstName: "I", lastName: "J", email: "ioff@example.com" },
  });
  // ACTIVE (approved) but not online -> must not be matched.
  await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE", isOnline: false } });

  const token = mockAuthAs({ sub: "rider-offline", groups: ["Rider"] });
  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
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
  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.driverId, null);
});

test("POST /api/trips rejects a Driver caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);
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

test("GET /api/trips/:id includes real payment data for the trip's own rider (not just Admin)", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-receipt-1", role: "RIDER", firstName: "C", lastName: "D", email: "receipt@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, finalFare: 12, status: "COMPLETED" },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 12, method: "CASH", status: "SUCCEEDED", paidAt: new Date() },
  });

  const token = mockAuthAs({ sub: "rider-receipt-1", groups: ["Rider"] });
  const res = await request(app).get(`/api/trips/${trip.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.payment?.method, "CASH");
  assert.equal(res.body.payment?.status, "SUCCEEDED");
  assert.equal(res.body.payment?.amount, 12);
});

test("PATCH /api/trips/:id/status lets the assigned Driver or an Admin advance trip status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-2", role: "DRIVER", firstName: "O", lastName: "P", email: "o@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });

  // Real forward flow: MATCHED -> IN_PROGRESS -> COMPLETED. The state machine
  // requires the intermediate step; jumping straight to COMPLETED is rejected
  // (proved separately below).
  const start = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(start.status, 200);
  assert.equal(start.body.status, "IN_PROGRESS");

  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 14 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.ok(res.body.completedAt);

  const notifications = await prisma.notification.findMany({ where: { userId: trip.riderId } });
  assert.ok(notifications.some((n) => n.type === "RIDE_STARTED"));
  assert.ok(notifications.some((n) => n.type === "RIDE_COMPLETED"));
  assert.ok(notifications.every((n) => n.referenceType === "TRIP" && n.referenceId === trip.id));

  // EI-1: the same completion event must also reach the driver (push) and
  // leave a truthful, actor-attributed record an admin can see (audit log)
  // — previously only the rider was ever told.
  const driverNotifications = await prisma.notification.findMany({ where: { userId: driverUser.id } });
  assert.ok(driverNotifications.some((n) => n.type === "RIDE_COMPLETED" && n.referenceId === trip.id));

  const auditEntries = await prisma.auditLog.findMany({ where: { entityId: trip.id, action: "TRIP_COMPLETED" } });
  assert.equal(auditEntries.length, 1);
  assert.equal(auditEntries[0].actorSub, "driver-sub-2");
});

test("PATCH /api/trips/:id/status rejects a Driver who isn't assigned to the trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-10", role: "RIDER", firstName: "Q", lastName: "R", email: "q@example.com" },
  });
  const assignedDriverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-10", role: "DRIVER", firstName: "S", lastName: "T", email: "s@example.com" },
  });
  const assignedDriver = await prisma.driver.create({ data: { userId: assignedDriverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: assignedDriver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  // A different driver, with no relation to this trip.
  const strangerUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-11", role: "DRIVER", firstName: "U", lastName: "V", email: "u@example.com" },
  });
  await prisma.driver.create({ data: { userId: strangerUser.id } });

  const token = mockAuthAs({ sub: "driver-sub-11", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    // A valid amount, so the request reaches (and is stopped at) the
    // ownership check rather than being rejected earlier for a bad body.
    .send({ status: "COMPLETED", finalFare: 20 });

  assert.equal(res.status, 403);

  const unchanged = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(unchanged?.status, "MATCHED");
  assert.equal(unchanged?.finalFare, null);
});

test("PATCH /api/trips/:id/status rejects an extreme finalFare from the assigned driver", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-far", role: "RIDER", firstName: "E", lastName: "F", email: "far@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-far", role: "DRIVER", firstName: "O", lastName: "P", email: "ofar@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 16, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "driver-far", groups: ["Driver"] });

  // 100x the estimate — well outside the allowed band.
  const extreme = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 1600 });
  assert.equal(extreme.status, 422);

  // Negative is rejected by the money schema (400) before the band check.
  const negative = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: -5 });
  assert.equal(negative.status, 400);

  // The trip was never mutated by either attempt.
  const unchanged = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(unchanged?.status, "IN_PROGRESS");
  assert.equal(unchanged?.finalFare, null);

  // A fare within the band (16 -> 20, 1.25x) is accepted.
  const ok = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 20 });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.finalFare, 20);
});

test("PATCH /api/trips/:id/status lets an Admin override the fare band (dispute correction)", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-adm", role: "RIDER", firstName: "E", lastName: "F", email: "adm@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-adm", role: "DRIVER", firstName: "O", lastName: "P", email: "oadm@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 16, status: "IN_PROGRESS" },
  });

  const token = mockAuthAs({ sub: "admin-fare", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 4 }); // below the driver band, allowed for Admin
  assert.equal(res.status, 200);
  assert.equal(res.body.finalFare, 4);
});

test("PATCH /api/trips/:id/status rejects a Finance Viewer admin, but a Super Admin's override is audited", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-perm", role: "RIDER", firstName: "E", lastName: "F", email: "perm@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-perm", role: "DRIVER", firstName: "O", lastName: "P", email: "operm@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 16, status: "MATCHED" },
  });
  await prisma.user.create({
    data: { cognitoSub: "finance-trips", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "fv-trips@example.com" },
  });

  const financeToken = mockAuthAs({ sub: "finance-trips", groups: ["Admin"] });
  const denied = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${financeToken}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(denied.status, 403);

  restoreAuth();
  const superToken = mockAuthAs({ sub: "super-trips", groups: ["Admin"] });
  const overridden = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${superToken}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(overridden.status, 200);

  const audit = await prisma.auditLog.findFirst({ where: { action: "TRIP_STATUS_OVERRIDDEN", entityId: trip.id } });
  assert.ok(audit);
});

test("GET /api/trips (Admin monitor) rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const res = await request(app).get("/api/trips").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/trips?q= searches server-side by trip id and by rider/driver name/email", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "search-rider", role: "RIDER", firstName: "Yemi", lastName: "Coker", email: "yemi@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "search-driver", role: "DRIVER", firstName: "Segun", lastName: "Balogun", email: "segun@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 20, status: "COMPLETED" },
  });
  await prisma.user.create({
    data: { cognitoSub: "search-rider-2", role: "RIDER", firstName: "Other", lastName: "Rider", email: "other@example.com" },
  });

  const token = mockAuthAs({ sub: "search-trips-admin", groups: ["Admin"] });

  const byId = await request(app).get("/api/trips").query({ q: trip.id }).set("Authorization", `Bearer ${token}`);
  assert.equal(byId.body.total, 1);
  assert.equal(byId.body.data[0].id, trip.id);

  const byRiderName = await request(app).get("/api/trips").query({ q: "coker" }).set("Authorization", `Bearer ${token}`);
  assert.equal(byRiderName.body.total, 1);
  assert.equal(byRiderName.body.data[0].id, trip.id);

  const byDriverEmail = await request(app).get("/api/trips").query({ q: "segun@example" }).set("Authorization", `Bearer ${token}`);
  assert.equal(byDriverEmail.body.total, 1);
  assert.equal(byDriverEmail.body.data[0].id, trip.id);

  const noMatch = await request(app).get("/api/trips").query({ q: "no-such-trip" }).set("Authorization", `Bearer ${token}`);
  assert.equal(noMatch.body.total, 0);
});

test("GET /api/trips/mine returns only the caller's own trips (as rider or driver)", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-mine", role: "RIDER", firstName: "M", lastName: "I", email: "mine@example.com" },
  });
  const otherRider = await prisma.user.create({
    data: { cognitoSub: "rider-other", role: "RIDER", firstName: "O", lastName: "T", email: "other@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-mine", role: "DRIVER", firstName: "D", lastName: "R", email: "dr@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });

  // One trip the rider owns, one assigned to the driver, one belonging to nobody relevant.
  const myTrip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 10 },
  });
  const driverTrip = await prisma.trip.create({
    data: { riderId: otherRider.id, driverId: driver.id, pickup: "C", destination: "D", estimatedFare: 12 },
  });
  await prisma.trip.create({
    data: { riderId: otherRider.id, pickup: "E", destination: "F", estimatedFare: 8 },
  });

  const riderToken = mockAuthAs({ sub: "rider-mine", groups: ["Rider"] });
  const riderRes = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(riderRes.status, 200);
  assert.equal(riderRes.body.total, 1);
  assert.equal(riderRes.body.data[0].id, myTrip.id);

  restoreAuth();
  const driverToken = mockAuthAs({ sub: "driver-mine", groups: ["Driver"] });
  const driverRes = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(driverRes.status, 200);
  assert.equal(driverRes.body.total, 1);
  assert.equal(driverRes.body.data[0].id, driverTrip.id);
});

test("POST /api/trips/:id/rating records the rating and updates the driver's average", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-rate", role: "RIDER", firstName: "R", lastName: "A", email: "rate@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-rate", role: "DRIVER", firstName: "D", lastName: "R", email: "drate@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, rating: 5 } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "COMPLETED" },
  });

  const token = mockAuthAs({ sub: "rider-rate", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rating`)
    .set("Authorization", `Bearer ${token}`)
    .send({ rating: 4 });
  assert.equal(res.status, 200);
  assert.equal(res.body.riderRating, 4);

  const updatedDriver = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(updatedDriver?.rating, 4);
});

test("POST /api/trips/:id/rating stores the optional comment (previously accepted by the schema but silently dropped)", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-rate-comment", role: "RIDER", firstName: "R", lastName: "A", email: "ratecomment@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-rate-comment", role: "DRIVER", firstName: "D", lastName: "R", email: "dratecomment@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, rating: 5 } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "COMPLETED" },
  });

  const token = mockAuthAs({ sub: "rider-rate-comment", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rating`)
    .set("Authorization", `Bearer ${token}`)
    .send({ rating: 5, comment: "Great driver, very punctual" });
  assert.equal(res.status, 200);
  assert.equal(res.body.riderComment, "Great driver, very punctual");

  // GET /trips/mine (what the driver's My Ratings screen reads) must return
  // the same comment via serializeTrip, not just the raw update response.
  restoreAuth();
  const driverToken = mockAuthAs({ sub: "driver-rate-comment", groups: ["Driver"] });
  const mine = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(mine.status, 200);
  assert.equal(mine.body.data[0].riderComment, "Great driver, very punctual");

  // Omitting the comment must not leave a stale value from some other write —
  // it should be explicitly null, never undefined/missing.
  restoreAuth();
  const trip2 = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "COMPLETED" },
  });
  const token2 = mockAuthAs({ sub: "rider-rate-comment", groups: ["Rider"] });
  const res2 = await request(app)
    .post(`/api/trips/${trip2.id}/rating`)
    .set("Authorization", `Bearer ${token2}`)
    .send({ rating: 3 });
  assert.equal(res2.status, 200);
  assert.equal(res2.body.riderComment, null);
});

test("POST /api/trips/:id/rating rejects a non-owner and an uncompleted trip", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-rate-2", role: "RIDER", firstName: "R", lastName: "A", email: "rate2@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-rate-2", role: "DRIVER", firstName: "D", lastName: "R", email: "drate2@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  // Owner but trip not completed -> 409.
  const ownerToken = mockAuthAs({ sub: "rider-rate-2", groups: ["Rider"] });
  const early = await request(app)
    .post(`/api/trips/${trip.id}/rating`)
    .set("Authorization", `Bearer ${ownerToken}`)
    .send({ rating: 5 });
  assert.equal(early.status, 409);

  // A different rider -> 403.
  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "rider-stranger", groups: ["Rider"] });
  const stranger = await request(app)
    .post(`/api/trips/${trip.id}/rating`)
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ rating: 5 });
  assert.equal(stranger.status, 403);
});

// --- P0 #10: server-authoritative fare ------------------------------------

test("POST /api/trips computes the fare from coordinates and ignores a client distanceKm", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-geo", role: "RIDER", firstName: "A", lastName: "B", email: "geo@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-geo", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    // Attacker tries to force a zero-distance fare; the server ignores it.
    .send({ ...tripInput, distanceKm: 0, durationMinutes: 0 });

  assert.equal(res.status, 201);
  assert.equal(res.body.estimatedFare, EXPECTED_FARE);
  assert.ok(res.body.distanceKm > 1, "server stored its own computed distance");
});

// --- P0 #8: matched-driver detail on the create response ------------------

test("POST /api/trips returns a safe driver summary when matched (no sensitive fields)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-disp", role: "RIDER", firstName: "G", lastName: "H", email: "disp@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-disp", role: "DRIVER", firstName: "Dele", lastName: "Okoro", email: "dele@example.com" },
  });
  const driver = await prisma.driver.create({
    data: { userId: driverUser.id, status: "ACTIVE", isOnline: true, rating: 4.7, ...locatedAt(PICKUP.lat, PICKUP.lng) },
  });
  await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Toyota", model: "Corolla", colour: "Silver", plateNumber: "LND-482-KJ", year: "2020" },
  });

  const token = mockAuthAs({ sub: "rider-disp", groups: ["Rider"] });
  const res = await request(app).post("/api/trips").set("Authorization", `Bearer ${token}`).send(tripInput);

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "OFFERED");
  assert.equal(res.body.driver.user.firstName, "Dele");
  assert.equal(res.body.driver.rating, 4.7);
  assert.equal(res.body.driver.vehicle.plateNumber, "LND-482-KJ");
  // The leak the raw relation used to carry must be gone.
  const blob = JSON.stringify(res.body);
  assert.ok(!blob.includes("dele@example.com"), "driver email must not be exposed");
  assert.ok(!blob.includes("driver-disp"), "driver cognitoSub must not be exposed");
});

// --- P0 #9: trip status state machine -------------------------------------

async function seedAssignedTrip(riderSub: string, driverSub: string, status: "REQUESTED" | "OFFERED" | "MATCHED" | "IN_PROGRESS" | "COMPLETED" | "CANCELLED") {
  const rider = await prisma.user.create({
    data: { cognitoSub: riderSub, role: "RIDER", firstName: "R", lastName: "R", email: `${riderSub}@example.com` },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: driverSub, role: "DRIVER", firstName: "D", lastName: "D", email: `${driverSub}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 16, status },
  });
  return trip;
}

test("POST /api/trips/:id/arrived notifies the rider, and is idempotent on a repeat call", async () => {
  const trip = await seedAssignedTrip("rider-arr-1", "driver-arr-1", "MATCHED");
  const token = mockAuthAs({ sub: "driver-arr-1", groups: ["Driver"] });

  const first = await request(app).post(`/api/trips/${trip.id}/arrived`).set("Authorization", `Bearer ${token}`).send();
  assert.equal(first.status, 200);
  assert.ok(first.body.arrivedAt);

  const notifications = await prisma.notification.findMany({ where: { userId: trip.riderId } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "RIDE_DRIVER_ARRIVED");

  // A repeat call must not push the arrival clock forward or double-notify.
  const second = await request(app).post(`/api/trips/${trip.id}/arrived`).set("Authorization", `Bearer ${token}`).send();
  assert.equal(second.status, 200);
  assert.equal(second.body.arrivedAt, first.body.arrivedAt);
  const stillOne = await prisma.notification.findMany({ where: { userId: trip.riderId } });
  assert.equal(stillOne.length, 1);
});

test("state machine rejects REQUESTED->COMPLETED (billing a trip never driven)", async () => {
  const trip = await seedAssignedTrip("rider-sm1", "driver-sm1", "REQUESTED");
  const token = mockAuthAs({ sub: "driver-sm1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 16 });
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, "INVALID_TRIP_TRANSITION");
  const after = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(after?.status, "REQUESTED");
  assert.equal(after?.finalFare, null);
});

test("state machine rejects reviving a COMPLETED trip to IN_PROGRESS", async () => {
  const trip = await seedAssignedTrip("rider-sm2", "driver-sm2", "COMPLETED");
  const token = mockAuthAs({ sub: "admin-sm", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(res.status, 409);
});

test("state machine forbids a driver-only actor from a dispute transition", async () => {
  const trip = await seedAssignedTrip("rider-sm3", "driver-sm3", "MATCHED");
  const token = mockAuthAs({ sub: "driver-sm3", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "DISPUTED" });
  assert.equal(res.status, 403);
});

// --- P0 #7: rider cancellation --------------------------------------------

test("POST /api/trips/:id/cancel lets the owning rider cancel a MATCHED trip", async () => {
  const trip = await seedAssignedTrip("rider-cx1", "driver-cx1", "MATCHED");
  const token = mockAuthAs({ sub: "rider-cx1", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");
  const after = await prisma.trip.findUnique({ where: { id: trip.id } });
  assert.equal(after?.status, "CANCELLED");
});

test("POST /api/trips/:id/cancel refuses to cancel an IN_PROGRESS trip", async () => {
  const trip = await seedAssignedTrip("rider-cx2", "driver-cx2", "IN_PROGRESS");
  const token = mockAuthAs({ sub: "rider-cx2", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, "TRIP_NOT_CANCELLABLE");
});

test("POST /api/trips/:id/cancel lets the owning rider cancel while a driver has only been OFFERED (not yet accepted)", async () => {
  const trip = await seedAssignedTrip("rider-cx4", "driver-cx4", "OFFERED");
  const token = mockAuthAs({ sub: "rider-cx4", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");
});

test("POST /api/trips/:id/cancel denies a rider who does not own the trip", async () => {
  const trip = await seedAssignedTrip("rider-cx3", "driver-cx3", "MATCHED");
  const token = mockAuthAs({ sub: "rider-not-owner", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("POST /api/trips/:id/rider-location lets the owning rider report a position while MATCHED", async () => {
  const trip = await seedAssignedTrip("rider-loc1", "driver-loc1", "MATCHED");
  const token = mockAuthAs({ sub: "rider-loc1", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5244, lng: 3.3792 });

  assert.equal(res.status, 200);
  assert.equal(res.body.tripId, trip.id);
  const stored = getRiderLocation(trip.id);
  assert.equal(stored?.lat, 6.5244);
  assert.equal(stored?.lng, 3.3792);
});

test("POST /api/trips/:id/rider-location works while IN_PROGRESS too", async () => {
  const trip = await seedAssignedTrip("rider-loc2", "driver-loc2", "IN_PROGRESS");
  const token = mockAuthAs({ sub: "rider-loc2", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.6, lng: 3.5 });
  assert.equal(res.status, 200);
});

test("POST /api/trips/:id/rider-location is refused before a driver is matched (REQUESTED)", async () => {
  const trip = await seedAssignedTrip("rider-loc3", "driver-loc3", "REQUESTED");
  const token = mockAuthAs({ sub: "rider-loc3", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5, lng: 3.4 });
  assert.equal(res.status, 409);
});

test("POST /api/trips/:id/rider-location is refused after the trip completes", async () => {
  const trip = await seedAssignedTrip("rider-loc4", "driver-loc4", "COMPLETED");
  const token = mockAuthAs({ sub: "rider-loc4", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5, lng: 3.4 });
  assert.equal(res.status, 409);
});

test("POST /api/trips/:id/rider-location denies a rider who does not own the trip", async () => {
  const trip = await seedAssignedTrip("rider-loc5", "driver-loc5", "MATCHED");
  const token = mockAuthAs({ sub: "rider-not-owner-loc", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5, lng: 3.4 });
  assert.equal(res.status, 403);
});

test("POST /api/trips/:id/rider-location rejects out-of-range coordinates", async () => {
  const trip = await seedAssignedTrip("rider-loc6", "driver-loc6", "MATCHED");
  const token = mockAuthAs({ sub: "rider-loc6", groups: ["Rider"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 999, lng: 3.4 });
  assert.equal(res.status, 400);
});

test("PATCH /api/trips/:id/status clears the cached rider location once a trip completes", async () => {
  const trip = await seedAssignedTrip("rider-loc7", "driver-loc7", "IN_PROGRESS");
  const riderToken = mockAuthAs({ sub: "rider-loc7", groups: ["Rider"] });
  await request(app)
    .post(`/api/trips/${trip.id}/rider-location`)
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ lat: 6.5, lng: 3.4 });
  assert.ok(getRiderLocation(trip.id));
  restoreAuth();

  const driverToken = mockAuthAs({ sub: "driver-loc7", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "COMPLETED", finalFare: 16 });
  assert.equal(res.status, 200);
  assert.equal(getRiderLocation(trip.id), undefined);
});
