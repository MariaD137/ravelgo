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

async function createRider(cognitoSub: string) {
  return prisma.user.create({
    data: { cognitoSub, role: "RIDER", firstName: "R", lastName: "I", email: `${cognitoSub}@example.com` },
  });
}

async function createDriver(cognitoSub: string, status: "PENDING_REVIEW" | "ACTIVE" = "ACTIVE") {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id, status } });
}

test("POST /api/courier-requests lets a Rider request a delivery", async () => {
  await createRider("rider-sub-1");
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/courier-requests")
    .set("Authorization", `Bearer ${token}`)
    .send({
      pickupAddress: "1 Main St",
      dropoffAddress: "2 Side St",
      packageDescription: "Documents",
      recipientName: "Sam",
      recipientPhone: "555-0100",
      estimatedFare: 12,
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
});

test("GET /api/courier-requests/available only shows unassigned requests to a Driver", async () => {
  const sender = await createRider("rider-sub-2");
  await createDriver("driver-sub-1");
  await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app).get("/api/courier-requests/available").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data.length, 1);
});

test("GET /api/courier-requests/available rejects a driver pending admin approval", async () => {
  const sender = await createRider("rider-sub-2b");
  await createDriver("driver-sub-1b", "PENDING_REVIEW");
  await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-1b", groups: ["Driver"] });
  const res = await request(app).get("/api/courier-requests/available").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
});

test("PATCH /api/courier-requests/:id/accept rejects a driver pending admin approval", async () => {
  const sender = await createRider("rider-sub-2c");
  await createDriver("driver-sub-1c", "PENDING_REVIEW");
  const req = await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-1c", groups: ["Driver"] });
  const res = await request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
});

test("GET /api/courier-requests/mine lists only my own assigned requests", async () => {
  const sender = await createRider("rider-sub-2d");
  const mine = await createDriver("driver-sub-1d");
  const other = await createDriver("driver-sub-1e");
  await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: mine.id,
      status: "MATCHED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });
  await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: other.id,
      status: "MATCHED",
      pickupAddress: "C",
      dropoffAddress: "D",
      packageDescription: "Bag",
      recipientName: "Y",
      recipientPhone: "555-2",
      estimatedFare: 15,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-1d", groups: ["Driver"] });
  const res = await request(app).get("/api/courier-requests/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data[0].driverId, mine.id);
});

test("PATCH /api/courier-requests/:id/accept matches a driver to the request", async () => {
  const sender = await createRider("rider-sub-3");
  await createDriver("driver-sub-2");
  const req = await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "MATCHED");
});

test("PATCH /api/courier-requests/:id/status rejects a driver not assigned to the request", async () => {
  const sender = await createRider("rider-sub-4");
  const assignedDriver = await createDriver("driver-sub-3");
  await createDriver("driver-sub-4");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: assignedDriver.id,
      status: "MATCHED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "DELIVERED" });

  assert.equal(res.status, 403);
});

test("GET /api/courier-requests/:id denies a stranger and allows the sender", async () => {
  const sender = await createRider("rider-sub-5");
  const req = await prisma.courierRequest.create({
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

  const ownerToken = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const ownerRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownerRes.status, 200);

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "rider-sub-6", groups: ["Rider"] });
  const strangerRes = await request(app)
    .get(`/api/courier-requests/${req.id}`)
    .set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 403);
});
