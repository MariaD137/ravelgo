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

  const notifications = await prisma.notification.findMany({ where: { userId: sender.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "DELIVERY_COURIER_ASSIGNED");
  assert.equal(notifications[0].referenceType, "COURIER_REQUEST");
  assert.equal(notifications[0].referenceId, req.id);
});

test("PATCH /api/courier-requests/:id/accept: two concurrent accepts for the same request — only one wins", async () => {
  const sender = await createRider("rider-race-1");
  await createDriver("driver-race-1");
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

  const token = mockAuthAs({ sub: "driver-race-1", groups: ["Driver"] });
  const [first, second] = await Promise.all([
    request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`),
    request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`),
  ]);
  const statuses = [first.status, second.status].sort();
  assert.deepEqual(statuses, [200, 409]);
});

test("A driver cannot accept a delivery while already on an active ride", async () => {
  const sender = await createRider("rider-conflict-2");
  const rider = await createRider("rider-conflict-3");
  const driver = await createDriver("driver-conflict-2");
  // This driver already has an active (MATCHED) ride.
  await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });
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

  const token = mockAuthAs({ sub: "driver-conflict-2", groups: ["Driver"] });
  const res = await request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 409);

  const unchanged = await prisma.courierRequest.findUnique({ where: { id: req.id } });
  assert.equal(unchanged?.status, "REQUESTED");
  assert.equal(unchanged?.driverId, null);
});

test("POST /api/courier-requests stores real pickup/dropoff coordinates when provided, and GET /:id returns them plus the courier's live location", async () => {
  await createRider("rider-coords-1");
  const driver = await createDriver("driver-coords-1");
  const senderToken = mockAuthAs({ sub: "rider-coords-1", groups: ["Rider"] });

  const created = await request(app)
    .post("/api/courier-requests")
    .set("Authorization", `Bearer ${senderToken}`)
    .send({
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      pickupLat: 6.5,
      pickupLng: 3.4,
      dropoffLat: 6.6,
      dropoffLng: 3.5,
    });
  assert.equal(created.status, 201);
  assert.equal(created.body.pickupLat, 6.5);
  assert.equal(created.body.pickupLng, 3.4);

  await prisma.courierRequest.update({ where: { id: created.body.id }, data: { driverId: driver.id, status: "MATCHED" } });

  restoreAuth();
  const driverToken = mockAuthAs({ sub: "driver-coords-1", groups: ["Driver"] });
  await request(app)
    .post("/api/drivers/me/location")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ lat: 6.55, lng: 3.45 });

  restoreAuth();
  const viewToken = mockAuthAs({ sub: "rider-coords-1", groups: ["Rider"] });
  const detail = await request(app).get(`/api/courier-requests/${created.body.id}`).set("Authorization", `Bearer ${viewToken}`);
  assert.equal(detail.status, 200);
  assert.equal(detail.body.pickupLat, 6.5);
  assert.equal(detail.body.dropoffLng, 3.5);
  assert.equal(detail.body.courierLat, 6.55);
  assert.equal(detail.body.courierPresence, "LIVE");
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

  const notifications = await prisma.notification.findMany({ where: { userId: sender.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "DELIVERY_PICKED_UP");
});

test("PATCH /api/courier-requests/:id/status notifies the sender on IN_TRANSIT and CANCELLED", async () => {
  const sender = await createRider("rider-sub-notif-transit");
  const driver = await createDriver("driver-sub-notif-transit");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "PICKED_UP",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });
  const token = mockAuthAs({ sub: "driver-sub-notif-transit", groups: ["Driver"] });

  const inTransit = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "IN_TRANSIT" });
  assert.equal(inTransit.status, 200);

  const cancelled = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "CANCELLED" });
  assert.equal(cancelled.status, 200);

  const notifications = await prisma.notification.findMany({ where: { userId: sender.id }, orderBy: { createdAt: "asc" } });
  assert.deepEqual(notifications.map((n) => n.type), ["DELIVERY_IN_TRANSIT", "DELIVERY_CANCELLED"]);
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

  const notifications = await prisma.notification.findMany({ where: { userId: sender.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "DELIVERY_DELIVERED");
  assert.ok(res.body.recipientSignatureUrl);

  restoreAuth();
  const senderToken = mockAuthAs({ sub: "rider-sub-10", groups: ["Rider"] });
  const getRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${senderToken}`);
  assert.equal(getRes.status, 200);
  assert.ok(getRes.body.deliveryPhotoUrl);
  assert.ok(getRes.body.recipientSignatureUrl);
});

test("GET /api/courier-requests/:id never leaks sender/driver email or cognitoSub", async () => {
  const sender = await createRider("rider-sub-leak");
  const driver = await createDriver("driver-sub-leak");
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

  const token = mockAuthAs({ sub: "rider-sub-leak", groups: ["Rider"] });
  const res = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  const raw = JSON.stringify(res.body);
  assert.ok(!raw.includes("@example.com"), "response must never include an email address");
  assert.ok(!raw.includes("rider-sub-leak"), "response must never include the sender's cognitoSub");
  assert.ok(!raw.includes("driver-sub-leak"), "response must never include the driver's cognitoSub");
  assert.equal(res.body.sender.firstName, "R");
  assert.equal(res.body.driver.user.firstName, "D");
});

test("GET /api/courier-requests/sent never leaks driver email or cognitoSub", async () => {
  const sender = await createRider("rider-sub-leak2");
  const driver = await createDriver("driver-sub-leak2");
  await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "rider-sub-leak2", groups: ["Rider"] });
  const res = await request(app).get("/api/courier-requests/sent").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  const raw = JSON.stringify(res.body);
  assert.ok(!raw.includes("@example.com"));
  assert.ok(!raw.includes("driver-sub-leak2"));
});

test("GET /api/courier-requests/available and /mine include the sender's name for the driver's card UI", async () => {
  const sender = await createRider("rider-sub-avail-name");
  await createDriver("driver-sub-avail-name");
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

  const token = mockAuthAs({ sub: "driver-sub-avail-name", groups: ["Driver"] });
  const available = await request(app).get("/api/courier-requests/available").set("Authorization", `Bearer ${token}`);
  assert.equal(available.status, 200);
  assert.equal(available.body.data[0].sender.firstName, "R");
  assert.ok(!JSON.stringify(available.body).includes("@example.com"));

  const acceptRes = await request(app)
    .patch(`/api/courier-requests/${available.body.data[0].id}/accept`)
    .set("Authorization", `Bearer ${token}`);
  assert.equal(acceptRes.status, 200);
  assert.equal(acceptRes.body.sender.firstName, "R");

  const mine = await request(app).get("/api/courier-requests/mine").set("Authorization", `Bearer ${token}`);
  assert.equal(mine.status, 200);
  assert.equal(mine.body.data[0].sender.firstName, "R");
});

test("GET /api/courier-requests/:id lets an ACTIVE driver preview an unassigned request, but not a PENDING_REVIEW driver", async () => {
  const sender = await createRider("rider-sub-preview");
  await createDriver("driver-sub-preview-active", "ACTIVE");
  await createDriver("driver-sub-preview-pending", "PENDING_REVIEW");
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

  const activeToken = mockAuthAs({ sub: "driver-sub-preview-active", groups: ["Driver"] });
  const activeRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${activeToken}`);
  assert.equal(activeRes.status, 200);

  restoreAuth();
  const pendingToken = mockAuthAs({ sub: "driver-sub-preview-pending", groups: ["Driver"] });
  const pendingRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${pendingToken}`);
  assert.equal(pendingRes.status, 403);

  // Once matched to another driver, it's no longer "available" to preview.
  await prisma.courierRequest.update({ where: { id: req.id }, data: { status: "MATCHED", driverId: (await createDriver("driver-sub-preview-taken")).id } });
  restoreAuth();
  const afterMatchToken = mockAuthAs({ sub: "driver-sub-preview-active", groups: ["Driver"] });
  const afterMatchRes = await request(app).get(`/api/courier-requests/${req.id}`).set("Authorization", `Bearer ${afterMatchToken}`);
  assert.equal(afterMatchRes.status, 403);
});

test("PATCH /api/courier-requests/:id/status notifies the assigned driver (not just the sender) on an admin override", async () => {
  const sender = await createRider("rider-sub-notify-driver");
  const driver = await createDriver("driver-sub-notify-driver");
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

  const superToken = mockAuthAs({ sub: "super-notify-driver", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${req.id}/status`)
    .set("Authorization", `Bearer ${superToken}`)
    .send({ status: "CANCELLED" });
  assert.equal(res.status, 200);

  const driverUser = await prisma.user.findUnique({ where: { id: driver.userId } });
  const driverNotifications = await prisma.notification.findMany({ where: { userId: driverUser!.id } });
  assert.equal(driverNotifications.length, 1);
  assert.equal(driverNotifications[0].type, "DELIVERY_CANCELLED");

  const senderNotifications = await prisma.notification.findMany({ where: { userId: sender.id } });
  assert.equal(senderNotifications.length, 1);
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

test("POST /api/courier-requests/:id/cancel lets the sender cancel a REQUESTED delivery", async () => {
  const sender = await createRider("rider-sub-cancel-1");
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

  const token = mockAuthAs({ sub: "rider-sub-cancel-1", groups: ["Rider"] });
  const res = await request(app).post(`/api/courier-requests/${req.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");

  const senderNotifications = await prisma.notification.findMany({ where: { userId: sender.id } });
  assert.equal(senderNotifications.length, 1);
  assert.equal(senderNotifications[0]!.type, "DELIVERY_CANCELLED");
});

test("POST /api/courier-requests/:id/cancel also notifies the already-matched driver", async () => {
  const sender = await createRider("rider-sub-cancel-2");
  const driver = await createDriver("driver-sub-cancel-1");
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

  const token = mockAuthAs({ sub: "rider-sub-cancel-2", groups: ["Rider"] });
  const res = await request(app).post(`/api/courier-requests/${req.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");

  const driverNotifications = await prisma.notification.findMany({ where: { userId: driver.userId } });
  assert.equal(driverNotifications.length, 1);
  assert.equal(driverNotifications[0]!.type, "DELIVERY_CANCELLED");
});

test("POST /api/courier-requests/:id/cancel rejects once the package has been picked up", async () => {
  const sender = await createRider("rider-sub-cancel-3");
  const driver = await createDriver("driver-sub-cancel-2");
  const req = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "PICKED_UP",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-3", groups: ["Rider"] });
  const res = await request(app).post(`/api/courier-requests/${req.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  const updated = await prisma.courierRequest.findUnique({ where: { id: req.id } });
  assert.equal(updated?.status, "PICKED_UP");
});

test("POST /api/courier-requests/:id/cancel rejects a caller who isn't the sender", async () => {
  const sender = await createRider("rider-sub-cancel-4");
  await createRider("rider-sub-cancel-5");
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

  const token = mockAuthAs({ sub: "rider-sub-cancel-5", groups: ["Rider"] });
  const res = await request(app).post(`/api/courier-requests/${req.id}/cancel`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});
