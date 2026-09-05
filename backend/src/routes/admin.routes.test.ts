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
