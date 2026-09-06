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

test("POST /api/courier-requests computes the price server-side from packageSize and ignores a client-supplied price", async () => {
  await createRider("rider-sub-1b");
  const token = mockAuthAs({ sub: "rider-sub-1b", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/courier-requests")
    .set("Authorization", `Bearer ${token}`)
    .send({
      pickupAddress: "1 Main St",
      dropoffAddress: "2 Side St",
      packageDescription: "A large box",
      packageSize: "LARGE",
      recipientName: "Sam",
      recipientPhone: "555-0100",
      estimatedFare: 1, // must be ignored
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.packageSize, "LARGE");
  assert.equal(res.body.estimatedFare, 2500);
});

test("GET /api/courier-requests/sent lists only the caller's own sent requests", async () => {
  const senderA = await createRider("rider-sub-1c");
  const tokenA = mockAuthAs({ sub: "rider-sub-1c", groups: ["Rider"] });
  await request(app)
    .post("/api/courier-requests")
    .set("Authorization", `Bearer ${tokenA}`)
    .send({
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
    });

  restoreAuth();
  await createRider("rider-sub-1d");
  const tokenB = mockAuthAs({ sub: "rider-sub-1d", groups: ["Rider"] });
  const res = await request(app).get("/api/courier-requests/sent").set("Authorization", `Bearer ${tokenB}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 0);

  restoreAuth();
  const tokenA2 = mockAuthAs({ sub: "rider-sub-1c", groups: ["Rider"] });
  const resA = await request(app).get("/api/courier-requests/sent").set("Authorization", `Bearer ${tokenA2}`);
  assert.equal(resA.status, 200);
  assert.equal(resA.body.length, 1);
  assert.equal(resA.body[0].senderId, senderA.id);
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

test("PATCH /api/courier-requests/:id/status accepts PICKED_UP and records pickedUpAt", async () => {
  const sender = await createRider("rider-sub-7");
  const driver = await createDriver("driver-sub-5");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "MATCHED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-5", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "PICKED_UP" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "PICKED_UP");
  assert.ok(res.body.pickedUpAt);
});

test("PATCH /api/courier-requests/:id/status rejects a Finance Viewer admin, but a Super Admin's override is audited", async () => {
  const sender = await createRider("rider-sub-perm");
  const driver = await createDriver("driver-sub-perm");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "MATCHED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });
  await prisma.user.create({
    data: { cognitoSub: "finance-courier", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "fv-courier@example.com" },
  });

  const financeToken = mockAuthAs({ sub: "finance-courier", groups: ["Admin"] });
  const denied = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${financeToken}`)
    .send({ status: "IN_TRANSIT" });
  assert.equal(denied.status, 403);

  restoreAuth();
  const superToken = mockAuthAs({ sub: "super-courier", groups: ["Admin"] });
  const overridden = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${superToken}`)
    .send({ status: "IN_TRANSIT" });
  assert.equal(overridden.status, 200);

  const audit = await prisma.auditLog.findFirst({ where: { action: "COURIER_REQUEST_STATUS_OVERRIDDEN", entityId: req.id } });
  assert.ok(audit);
});

test("PATCH /api/courier-requests/:id/status rejects DELIVERED without a delivery photo and signature", async () => {
  const sender = await createRider("rider-sub-8");
  const driver = await createDriver("driver-sub-6");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "IN_TRANSIT",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "DELIVERED" });

  assert.equal(res.status, 400);

  const stillInTransit = await prisma.courierRequest.findUnique({ where: { id: req.id } });
  assert.equal(stillInTransit?.status, "IN_TRANSIT");
});

test("PATCH /api/courier-requests/:id/status rejects a proof-of-delivery key that doesn't belong to the caller", async () => {
  const sender = await createRider("rider-sub-9");
  const driver = await createDriver("driver-sub-7");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "IN_TRANSIT",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-7", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({
      status: "DELIVERED",
      deliveryPhotoKey: "someone-elses-sub/photo.jpg",
      recipientSignatureKey: "driver-sub-7/sig.png",
    });

  assert.equal(res.status, 403);
});

test("PATCH /api/courier-requests/:id/status marks DELIVERED with proof of delivery and returns signed URLs", async () => {
  const sender = await createRider("rider-sub-10");
  const driver = await createDriver("driver-sub-8");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "IN_TRANSIT",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-8", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({
      status: "DELIVERED",
      deliveryPhotoKey: "driver-sub-8/photo.jpg",
      recipientSignatureKey: "driver-sub-8/sig.png",
    });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "DELIVERED");
  assert.ok(res.body.deliveredAt);
  assert.ok(res.body.deliveryPhotoUrl);
  assert.ok(res.body.recipientSignatureUrl);

  restoreAuth();
  const senderToken = mockAuthAs({ sub: "rider-sub-10", groups: ["Rider"] });
  const getRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${senderToken}`);
  assert.equal(getRes.status, 200);
  assert.ok(getRes.body.deliveryPhotoUrl);
  assert.ok(getRes.body.recipientSignatureUrl);
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
