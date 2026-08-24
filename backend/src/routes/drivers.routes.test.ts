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

async function createDriver(sub: string, status: "PENDING_REVIEW" | "ACTIVE" | "SUSPENDED" = "ACTIVE") {
  const user = await prisma.user.create({
    data: { cognitoSub: sub, role: "DRIVER", firstName: "F", lastName: "L", email: `${sub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id, status } });
}

test("PATCH /api/drivers/me/online lets an ACTIVE driver go online, opening a session", async () => {
  const driver = await createDriver("driver-online-1", "ACTIVE");
  const token = mockAuthAs({ sub: "driver-online-1", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: true });

  assert.equal(res.status, 200);
  assert.equal(res.body.isOnline, true);
  assert.ok(res.body.lastOnlineAt);

  const sessions = await prisma.driverOnlineSession.findMany({ where: { driverId: driver.id } });
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].endedAt, null);
});

test("PATCH /api/drivers/me/online rejects a PENDING_REVIEW driver going online", async () => {
  await createDriver("driver-online-2", "PENDING_REVIEW");
  const token = mockAuthAs({ sub: "driver-online-2", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: true });

  assert.equal(res.status, 403);
  assert.match(res.body.error.message, /pending review/i);
});

test("PATCH /api/drivers/me/online rejects a SUSPENDED driver going online, but allows going offline", async () => {
  const driver = await createDriver("driver-online-3", "SUSPENDED");
  const token = mockAuthAs({ sub: "driver-online-3", groups: ["Driver"] });

  const blocked = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: true });
  assert.equal(blocked.status, 403);
  assert.match(blocked.body.error.message, /suspended/i);

  // A suspended driver can always go offline — never trapped "online".
  await prisma.driver.update({ where: { id: driver.id }, data: { isOnline: true, lastOnlineAt: new Date() } });
  const allowed = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: false });
  assert.equal(allowed.status, 200);
  assert.equal(allowed.body.isOnline, false);
});

test("PATCH /api/drivers/me/online going offline closes the open session", async () => {
  const driver = await createDriver("driver-online-4", "ACTIVE");
  const token = mockAuthAs({ sub: "driver-online-4", groups: ["Driver"] });

  await request(app).patch("/api/drivers/me/online").set("Authorization", `Bearer ${token}`).send({ isOnline: true });
  const res = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: false });

  assert.equal(res.status, 200);
  assert.equal(res.body.isOnline, false);

  const sessions = await prisma.driverOnlineSession.findMany({ where: { driverId: driver.id } });
  assert.equal(sessions.length, 1);
  assert.ok(sessions[0].endedAt);
});

test("PATCH /api/drivers/me/online is idempotent — repeated online calls don't open duplicate sessions", async () => {
  const driver = await createDriver("driver-online-5", "ACTIVE");
  const token = mockAuthAs({ sub: "driver-online-5", groups: ["Driver"] });

  for (let i = 0; i < 3; i++) {
    const res = await request(app)
      .patch("/api/drivers/me/online")
      .set("Authorization", `Bearer ${token}`)
      .send({ isOnline: true });
    assert.equal(res.status, 200);
  }

  const sessions = await prisma.driverOnlineSession.findMany({ where: { driverId: driver.id } });
  assert.equal(sessions.length, 1);
});

test("PATCH /api/drivers/me/online handles concurrent online requests without duplicate open sessions", async () => {
  const driver = await createDriver("driver-online-6", "ACTIVE");
  const token = mockAuthAs({ sub: "driver-online-6", groups: ["Driver"] });

  const [a, b] = await Promise.all([
    request(app).patch("/api/drivers/me/online").set("Authorization", `Bearer ${token}`).send({ isOnline: true }),
    request(app).patch("/api/drivers/me/online").set("Authorization", `Bearer ${token}`).send({ isOnline: true }),
  ]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);

  const openSessions = await prisma.driverOnlineSession.findMany({ where: { driverId: driver.id, endedAt: null } });
  assert.equal(openSessions.length, 1);
});

test("GET /api/drivers/me/summary scopes strictly to the caller — never another driver's data", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-summary-1", role: "RIDER", firstName: "R", lastName: "I", email: "r@example.com" },
  });
  const driverA = await createDriver("driver-summary-a", "ACTIVE");
  const driverB = await createDriver("driver-summary-b", "ACTIVE");

  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driverA.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 100,
      status: "COMPLETED",
      completedAt: new Date(),
    },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 100, status: "SUCCEEDED" },
  });

  const tokenA = mockAuthAs({ sub: "driver-summary-a", groups: ["Driver"] });
  const resA = await request(app).get("/api/drivers/me/summary").set("Authorization", `Bearer ${tokenA}`);
  assert.equal(resA.status, 200);
  assert.equal(resA.body.tripsToday, 1);
  assert.equal(resA.body.grossFareToday, 100);
  assert.equal(resA.body.platformFeeToday, 20);
  assert.equal(resA.body.netEarningsToday, 80);

  restoreAuth();
  const tokenB = mockAuthAs({ sub: "driver-summary-b", groups: ["Driver"] });
  const resB = await request(app).get("/api/drivers/me/summary").set("Authorization", `Bearer ${tokenB}`);
  assert.equal(resB.status, 200);
  assert.equal(resB.body.tripsToday, 0);
  assert.equal(resB.body.grossFareToday, 0);
  void driverB;
});

test("GET /api/drivers/me/summary computes online hours from persisted sessions, not a live timer", async () => {
  const driver = await createDriver("driver-summary-c", "ACTIVE");
  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  // A closed 2-hour session earlier today, persisted directly (bypassing
  // the toggle endpoint) to prove the summary reads from the session log
  // itself rather than from any in-request computation.
  await prisma.driverOnlineSession.create({
    data: {
      driverId: driver.id,
      startedAt: new Date(startOfDay.getTime() + 60 * 60 * 1000),
      endedAt: new Date(startOfDay.getTime() + 3 * 60 * 60 * 1000),
    },
  });

  const token = mockAuthAs({ sub: "driver-summary-c", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers/me/summary").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.onlineHoursToday, 2);
});
