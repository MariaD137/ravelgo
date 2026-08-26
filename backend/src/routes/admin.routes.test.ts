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

test("GET /api/admin/dashboard rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app).get("/api/admin/dashboard").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/admin/dashboard returns real KPI counts", async () => {
  const riderUser = await prisma.user.create({
    data: { cognitoSub: "rider-sub-2", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-1", role: "DRIVER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  // ACTIVE (verification/approval) and isOnline (presence) are independent
  // — an approved driver who hasn't gone online yet must not count as
  // "online". A second ACTIVE-but-offline driver below proves the
  // dashboard actually distinguishes the two.
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE", isOnline: true } });
  const offlineDriverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-2", role: "DRIVER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  await prisma.driver.create({ data: { userId: offlineDriverUser.id, status: "ACTIVE", isOnline: false } });
  await prisma.trip.create({
    data: { riderId: riderUser.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, status: "IN_PROGRESS" },
  });
  await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", status: "PENDING" } });
  await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "AAA-1", status: "SUBMITTED" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/dashboard").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.activeTrips, 1);
  assert.equal(res.body.onlineDrivers, 1);
  assert.equal(res.body.pendingApprovals, 2);
});

test("GET /api/admin/drivers/presence rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });
  const res = await request(app).get("/api/admin/drivers/presence").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/admin/drivers/presence returns fleet counts and per-driver presence", async () => {
  const onlineUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-10", role: "DRIVER", firstName: "On", lastName: "Line", email: "on@example.com" },
  });
  const onlineDriver = await prisma.driver.create({
    data: { userId: onlineUser.id, status: "ACTIVE", isOnline: true, lastOnlineAt: new Date() },
  });
  await prisma.vehicle.create({
    data: { driverId: onlineDriver.id, brand: "Toyota", model: "Camry", colour: "Black", plateNumber: "XYZ-1", year: "2021", isPrimary: true },
  });

  const offlineUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-11", role: "DRIVER", firstName: "Off", lastName: "Line", email: "off@example.com" },
  });
  await prisma.driver.create({ data: { userId: offlineUser.id, status: "PENDING_REVIEW", isOnline: false } });

  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/drivers/presence").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.counts.total, 2);
  assert.equal(res.body.counts.online, 1);
  assert.equal(res.body.counts.offline, 1);
  assert.equal(res.body.counts.pendingReview, 1);

  const online = res.body.drivers.find((d: { id: string }) => d.id === onlineDriver.id);
  assert.ok(online);
  assert.equal(online.isOnline, true);
  assert.ok(online.onlineSince);
  assert.equal(online.vehicle, "Toyota Camry (XYZ-1)");
  // No location has been pushed over WS for this driver in this test — must
  // say so honestly rather than fabricate coordinates.
  assert.equal(online.location, "Location unavailable");
});
