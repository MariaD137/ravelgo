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

test("POST /api/drivers/me creates a user + driver profile together", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Kay", lastName: "D", email: "kay@example.com" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  const user = await prisma.user.findUnique({ where: { cognitoSub: "driver-sub-1" } });
  assert.ok(user);
  assert.equal(user?.role, "DRIVER");
});

test("GET /api/drivers/me 404s before a driver profile exists", async () => {
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/drivers rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/drivers/:id/status lets an Admin suspend a driver", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-4", role: "DRIVER", firstName: "Lo", lastName: "P", email: "lo@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "SUSPENDED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "SUSPENDED");
});

test("PATCH /api/drivers/me/online toggles real presence, persisted in Postgres", async () => {
  const token = mockAuthAs({ sub: "driver-sub-online-1", groups: ["Driver"] });
  await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "On", lastName: "Line", email: "online1@example.com" });

  const goOnline = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ online: true });
  assert.equal(goOnline.status, 200);
  assert.equal(goOnline.body.online, true);

  const persisted = await prisma.driver.findFirst({ where: { user: { cognitoSub: "driver-sub-online-1" } } });
  assert.equal(persisted?.online, true);

  const goOffline = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ online: false });
  assert.equal(goOffline.status, 200);
  assert.equal(goOffline.body.online, false);
});

test("PATCH /api/drivers/me/online 404s before a driver profile exists", async () => {
  const token = mockAuthAs({ sub: "driver-sub-online-2", groups: ["Driver"] });
  const res = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ online: true });
  assert.equal(res.status, 404);
});

test("GET /api/drivers/me/assignment returns null when the driver has no active job", async () => {
  const token = mockAuthAs({ sub: "driver-sub-assign-1", groups: ["Driver"] });
  await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Free", lastName: "D", email: "freed@example.com" });

  const res = await request(app).get("/api/drivers/me/assignment").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body, null);
});

test("GET /api/drivers/me/assignment returns the real ACTIVE DriverAssignment row for a matched ride", async () => {
  await prisma.pricingRule.deleteMany();
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 5, perKm: 1, perMinute: 0.1, active: true } });

  const driverToken = mockAuthAs({ sub: "driver-sub-assign-2", groups: ["Driver"] });
  const driverRes = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Busy", lastName: "D", email: "busyd@example.com" });
  await prisma.driver.update({ where: { id: driverRes.body.id }, data: { status: "ACTIVE", online: true } });

  const riderToken = mockAuthAs({ sub: "rider-sub-assign-2", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Rida", lastName: "R", email: "ridar@example.com" });
  const tripRes = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", distanceKm: 2, durationMinutes: 5 });
  assert.equal(tripRes.body.status, "MATCHED");

  // mockAuthAs replaces the verifier's mock wholesale — re-mock the driver
  // identity (same deterministic `mock.<sub>` token) since riderToken was
  // mocked most recently above.
  const driverTokenAgain = mockAuthAs({ sub: "driver-sub-assign-2", groups: ["Driver"] });
  const assignRes = await request(app)
    .get("/api/drivers/me/assignment")
    .set("Authorization", `Bearer ${driverTokenAgain}`);

  assert.equal(assignRes.status, 200);
  assert.equal(assignRes.body.assignmentType, "RIDE");
  assert.equal(assignRes.body.assignmentId, tripRes.body.id);
  assert.equal(assignRes.body.status, "ACTIVE");
  await prisma.pricingRule.deleteMany();
});
