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
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
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
