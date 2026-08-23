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

test("GET /api/admin/reports/weekly reflects real completed trips and paid revenue", async () => {
  const riderUser = await prisma.user.create({
    data: { cognitoSub: "rider-sub-report-1", role: "RIDER", firstName: "A", lastName: "B", email: "report1@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-report-1", role: "DRIVER", firstName: "C", lastName: "D", email: "report1d@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: {
      riderId: riderUser.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 100,
      finalFare: 100,
      status: "COMPLETED",
      completedAt: new Date(),
    },
  });
  await prisma.payment.create({
    data: { tripId: trip.id, userId: riderUser.id, amount: 100, status: "SUCCEEDED", paidAt: new Date() },
  });

  // A trip completed over a week ago must not count toward "this week".
  const oldTrip = await prisma.trip.create({
    data: {
      riderId: riderUser.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 50,
      finalFare: 50,
      status: "COMPLETED",
      completedAt: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000),
    },
  });
  await prisma.payment.create({
    data: { tripId: oldTrip.id, userId: riderUser.id, amount: 50, status: "SUCCEEDED", paidAt: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000) },
  });

  const token = mockAuthAs({ sub: "admin-sub-report-1", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/reports/weekly").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.tripsCompletedThisWeek, 1);
  assert.equal(res.body.revenueThisWeek, 100);
});

test("POST /api/admin/me then GET /api/admin/me round-trips a real Postgres row", async () => {
  const token = mockAuthAs({ sub: "admin-sub-me-1", groups: ["Admin"] });

  const created = await request(app)
    .post("/api/admin/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Ops", lastName: "Admin", email: "opsadmin@example.com" });
  assert.equal(created.status, 201);
  assert.equal(created.body.role, "ADMIN");

  const fetched = await request(app).get("/api/admin/me").set("Authorization", `Bearer ${token}`);
  assert.equal(fetched.status, 200);
  assert.equal(fetched.body.id, created.body.id);
  assert.equal(fetched.body.email, "opsadmin@example.com");
});
