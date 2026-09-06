import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";
import { recordDriverLocation, resetRealtimeState } from "../realtime/hub";

beforeEach(() => {
  resetRealtimeState();
  return resetDb();
});
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
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE", isOnline: true } });
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

test("GET /api/admin/analytics buckets real revenue and completed trips by day and rejects non-admins", async () => {
  const riderUser = await prisma.user.create({
    data: { cognitoSub: "rider-sub-analytics", role: "RIDER", firstName: "A", lastName: "B", email: "analytics-rider@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-analytics", role: "DRIVER", firstName: "C", lastName: "D", email: "analytics-driver@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const now = new Date();

  const trip = await prisma.trip.create({
    data: {
      riderId: riderUser.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 5000,
      status: "COMPLETED",
      completedAt: now,
    },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: riderUser.id, amount: 5000, status: "SUCCEEDED", paidAt: now },
  });

  const token = mockAuthAs({ sub: "admin-sub-analytics", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/analytics").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.days.length, 7);
  const totalRevenue = res.body.days.reduce((sum: number, d: { revenue: number }) => sum + d.revenue, 0);
  const totalCompleted = res.body.days.reduce((sum: number, d: { completedTrips: number }) => sum + d.completedTrips, 0);
  assert.equal(totalRevenue, 5000);
  assert.equal(totalCompleted, 1);
  // No fabricated "driver online hours" metric.
  assert.equal(res.body.hours, undefined);

  restoreAuth();
  const riderToken = mockAuthAs({ sub: "rider-sub-analytics", groups: ["Rider"] });
  const denied = await request(app).get("/api/admin/analytics").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(denied.status, 403);
});

test("GET /api/admin/audit returns audit entries for an Admin and rejects others", async () => {
  await prisma.auditLog.create({
    data: { actorSub: "admin-sub-1", action: "DRIVER_STATUS_CHANGED", entityType: "Driver", entityId: "drv-1" },
  });

  const adminToken = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const ok = await request(app).get("/api/admin/audit").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.total, 1);
  assert.equal(ok.body.data[0].action, "DRIVER_STATUS_CHANGED");

  restoreAuth();
  const riderToken = mockAuthAs({ sub: "rider-x", groups: ["Rider"] });
  const denied = await request(app).get("/api/admin/audit").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(denied.status, 403);
});

test("GET /api/admin/live-map only draws drivers who have reported a real coordinate, coloured by real state", async () => {
  // Available: online, no active job, no reported coordinate at all yet -> not drawn.
  const idleUser = await prisma.user.create({
    data: { cognitoSub: "map-idle", role: "DRIVER", firstName: "I", lastName: "D", email: "idle@example.com" },
  });
  await prisma.driver.create({ data: { userId: idleUser.id, status: "ACTIVE", isOnline: true } });

  // Available WITH a reported coordinate -> AVAILABLE (green).
  const availUser = await prisma.user.create({
    data: { cognitoSub: "map-avail", role: "DRIVER", firstName: "A", lastName: "V", email: "avail@example.com" },
  });
  const availDriver = await prisma.driver.create({ data: { userId: availUser.id, status: "ACTIVE", isOnline: true } });
  recordDriverLocation(availDriver.id, 6.5, 3.4);

  // On an active trip -> ON_TRIP (blue), and the trip shows up in `trips`.
  const riderUser = await prisma.user.create({
    data: { cognitoSub: "map-rider", role: "RIDER", firstName: "R", lastName: "I", email: "rider-map@example.com" },
  });
  const busyUser = await prisma.user.create({
    data: { cognitoSub: "map-busy", role: "DRIVER", firstName: "B", lastName: "U", email: "busy@example.com" },
  });
  const busyDriver = await prisma.driver.create({ data: { userId: busyUser.id, status: "ACTIVE", isOnline: true } });
  recordDriverLocation(busyDriver.id, 6.6, 3.5);
  const trip = await prisma.trip.create({
    data: {
      riderId: riderUser.id,
      driverId: busyDriver.id,
      pickup: "Ikeja",
      destination: "Lekki",
      pickupLat: 6.6,
      pickupLng: 3.5,
      dropoffLat: 6.45,
      dropoffLng: 3.47,
      estimatedFare: 5000,
      status: "IN_PROGRESS",
    },
  });

  const token = mockAuthAs({ sub: "admin-map-1", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/live-map").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  const drivers = res.body.drivers as { driverId: string; markerStatus: string }[];
  assert.equal(drivers.length, 2); // the idle driver with no coordinate is never drawn

  const avail = drivers.find((d) => d.driverId === availDriver.id);
  assert.equal(avail?.markerStatus, "AVAILABLE");
  const busy = drivers.find((d) => d.driverId === busyDriver.id);
  assert.equal(busy?.markerStatus, "ON_TRIP");

  assert.equal(res.body.trips.length, 1);
  assert.equal(res.body.trips[0].id, trip.id);
  assert.equal(res.body.trips[0].pickup, "Ikeja");
});

test("GET /api/admin/live-map marks a driver with an open emergency alert as INCIDENT, overriding any other state", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "map-incident", role: "DRIVER", firstName: "N", lastName: "C", email: "incident@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", isOnline: true } });
  recordDriverLocation(driver.id, 6.5, 3.4);
  await prisma.emergencyAlert.create({ data: { userId: user.id, type: "SOS", status: "OPEN" } });

  const token = mockAuthAs({ sub: "admin-map-2", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/live-map").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.drivers[0].markerStatus, "INCIDENT");
});

test("GET /api/admin/live-map rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-map", groups: ["Rider"] });
  const res = await request(app).get("/api/admin/live-map").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
