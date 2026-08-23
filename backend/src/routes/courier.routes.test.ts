import assert from "node:assert/strict";
import { after, afterEach, beforeEach, mock, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { verifier } from "../middleware/auth";
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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  // ACTIVE — an admin-approved driver, since most of this file's tests are
  // about courier business logic, not the approval gate itself (see the
  // dedicated "pending/suspended driver" test below for that).
  return prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
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

test("PATCH /api/courier-requests/:id/accept rejects a driver who isn't ACTIVE (pending approval or suspended)", async () => {
  const sender = await createRider("rider-sub-notactive-1");
  const pendingDriver = await prisma.user.create({
    data: { cognitoSub: "driver-sub-pending-1", role: "DRIVER", firstName: "P", lastName: "D", email: "pd1@example.com" },
  });
  await prisma.driver.create({ data: { userId: pendingDriver.id } }); // default PENDING_REVIEW
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

  const token = mockAuthAs({ sub: "driver-sub-pending-1", groups: ["Driver"] });
  const res = await request(app).patch(`/api/courier-requests/${req.id}/accept`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
  const stillOpen = await prisma.courierRequest.findUniqueOrThrow({ where: { id: req.id } });
  assert.equal(stillOpen.status, "REQUESTED", "a pending/suspended driver must not be able to claim the request");
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

test("PATCH /api/courier-requests/:id/accept: two drivers racing for the same request — exactly one wins", async () => {
  const sender = await createRider("rider-sub-race-1");
  await createDriver("driver-sub-race-a");
  await createDriver("driver-sub-race-b");
  const courierReq = await prisma.courierRequest.create({
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

  // Both drivers need a simultaneously-valid token for this test, which
  // mockAuthAs() (one active mock at a time) doesn't support — mock the
  // verifier directly to accept either.
  const tokenA = `mock.driver-sub-race-a`;
  const tokenB = `mock.driver-sub-race-b`;
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate === tokenA) return { sub: "driver-sub-race-a", "cognito:groups": ["Driver"] } as never;
    if (candidate === tokenB) return { sub: "driver-sub-race-b", "cognito:groups": ["Driver"] } as never;
    throw new Error("invalid token");
  });

  const [resA, resB] = await Promise.all([
    request(app).patch(`/api/courier-requests/${courierReq.id}/accept`).set("Authorization", `Bearer ${tokenA}`),
    request(app).patch(`/api/courier-requests/${courierReq.id}/accept`).set("Authorization", `Bearer ${tokenB}`),
  ]);

  const statuses = [resA.status, resB.status].sort();
  assert.deepEqual(statuses, [200, 409]);

  const final = await prisma.courierRequest.findUnique({ where: { id: courierReq.id } });
  assert.equal(final?.status, "MATCHED");
  assert.ok(final?.driverId);
});

test("PATCH /api/courier-requests/:id/accept rejects a driver already MATCHED on a ride (Ride->Courier)", async () => {
  const sender = await createRider("rider-sub-busy-1");
  const driver = await createDriver("driver-sub-busy-1");
  // Simulate the driver already holding an active RIDE assignment, the same
  // row shape matchDriverToTrip() would have created.
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RIDE", assignmentId: "some-trip-id" },
  });
  const courierReq = await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-busy-1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${courierReq.id}/accept`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  assert.equal(res.body.code, "DRIVER_BUSY");
  assert.equal(res.body.activeAssignmentType, "RIDE");

  const final = await prisma.courierRequest.findUnique({ where: { id: courierReq.id } });
  assert.equal(final?.status, "REQUESTED");
  assert.equal(final?.driverId, null);
});

test("PATCH /api/courier-requests/:id/accept rejects a driver already on another active courier request (Courier->Courier)", async () => {
  const sender = await createRider("rider-sub-busy-2");
  // A second, distinct sender for the second request — one sender can never
  // legitimately have two simultaneously-open CourierRequests
  // (CourierRequest_senderId_open_unique), so this fixture needs two.
  const secondSender = await createRider("rider-sub-busy-2b");
  const driver = await createDriver("driver-sub-busy-2");
  const firstReq = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "MATCHED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box 1",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "COURIER", assignmentId: firstReq.id },
  });
  const secondReq = await prisma.courierRequest.create({
    data: {
      senderId: secondSender.id,
      pickupAddress: "C",
      dropoffAddress: "D",
      packageDescription: "Box 2",
      recipientName: "Y",
      recipientPhone: "555-2",
      estimatedFare: 15,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-busy-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${secondReq.id}/accept`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  assert.equal(res.body.code, "DRIVER_BUSY");
  assert.equal(res.body.activeAssignmentType, "COURIER");
  assert.equal(res.body.activeAssignmentId, firstReq.id);
});

test("PATCH /api/courier-requests/:id/accept: one driver racing to accept two different requests — exactly one wins (concurrency)", async () => {
  const sender = await createRider("rider-sub-race-2");
  // A second, distinct sender — see the Courier->Courier test above for why
  // one sender can't hold two open requests at once.
  const secondSender = await createRider("rider-sub-race-2b");
  const driver = await createDriver("driver-sub-race-c");
  const reqA = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box A",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });
  const reqB = await prisma.courierRequest.create({
    data: {
      senderId: secondSender.id,
      pickupAddress: "C",
      dropoffAddress: "D",
      packageDescription: "Box B",
      recipientName: "Y",
      recipientPhone: "555-2",
      estimatedFare: 12,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-race-c", groups: ["Driver"] });
  const [resA, resB] = await Promise.all([
    request(app).patch(`/api/courier-requests/${reqA.id}/accept`).set("Authorization", `Bearer ${token}`),
    request(app).patch(`/api/courier-requests/${reqB.id}/accept`).set("Authorization", `Bearer ${token}`),
  ]);

  const statuses = [resA.status, resB.status].sort();
  assert.deepEqual(statuses, [200, 409]);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1);

  const [finalA, finalB] = await Promise.all([
    prisma.courierRequest.findUnique({ where: { id: reqA.id } }),
    prisma.courierRequest.findUnique({ where: { id: reqB.id } }),
  ]);
  const matchedCount = [finalA, finalB].filter((r) => r?.status === "MATCHED").length;
  assert.equal(matchedCount, 1);
});

test("PATCH /api/courier-requests/:id/status releases the driver's assignment on DELIVERED", async () => {
  const sender = await createRider("rider-sub-release-1");
  const driver = await createDriver("driver-sub-release-1");
  const courierReq = await prisma.courierRequest.create({
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
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "COURIER", assignmentId: courierReq.id },
  });

  const token = mockAuthAs({ sub: "driver-sub-release-1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${courierReq.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "DELIVERED" });

  assert.equal(res.status, 200);

  const assignment = await prisma.driverAssignment.findFirst({ where: { driverId: driver.id } });
  assert.equal(assignment?.status, "ENDED");
  assert.ok(assignment?.endedAt);
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

test("PATCH /api/courier-requests/:id/status rejects jumping MATCHED straight to DELIVERED", async () => {
  const sender = await createRider("rider-sub-illegal-1");
  const driver = await createDriver("driver-sub-illegal-1");
  const courierReq = await prisma.courierRequest.create({
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

  const token = mockAuthAs({ sub: "driver-sub-illegal-1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${courierReq.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "DELIVERED" });

  assert.equal(res.status, 409);
  const unchanged = await prisma.courierRequest.findUnique({ where: { id: courierReq.id } });
  assert.equal(unchanged?.status, "MATCHED");
});

test("PATCH /api/courier-requests/:id/status rejects updating an already-DELIVERED request", async () => {
  const sender = await createRider("rider-sub-illegal-2");
  const driver = await createDriver("driver-sub-illegal-2");
  const courierReq = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      status: "DELIVERED",
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
      deliveredAt: new Date(),
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-illegal-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/courier-requests/${courierReq.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "CANCELLED" });

  assert.equal(res.status, 409);
});

test("CourierRequest.paymentStatus defaults to NOT_CONFIGURED (explicit non-payment state, Stripe not yet integrated)", async () => {
  await createRider("rider-sub-payment-1");
  const token = mockAuthAs({ sub: "rider-sub-payment-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/courier-requests")
    .set("Authorization", `Bearer ${token}`)
    .send({
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.paymentStatus, "NOT_CONFIGURED");
});

test("PATCH /api/courier-requests/:id/accept 404s cleanly on a malformed/garbage id (not a 500)", async () => {
  await createDriver("driver-sub-malformed-1");
  const token = mockAuthAs({ sub: "driver-sub-malformed-1", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/courier-requests/not-a-real-id;drop-table/accept")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/courier-requests/:id 404s cleanly on a malformed/garbage id (not a 500)", async () => {
  await createRider("rider-sub-malformed-1");
  const token = mockAuthAs({ sub: "rider-sub-malformed-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/courier-requests/' OR 1=1 --")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/courier-requests/mine returns only the calling sender's own requests, most recent first", async () => {
  const sender = await createRider("rider-sub-mine-1");
  const otherSender = await createRider("rider-sub-mine-2");
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
  await prisma.courierRequest.create({
    data: {
      senderId: otherSender.id,
      pickupAddress: "C",
      dropoffAddress: "D",
      packageDescription: "Box2",
      recipientName: "Y",
      recipientPhone: "555-2",
      estimatedFare: 15,
    },
  });

  const token = mockAuthAs({ sub: "rider-sub-mine-1", groups: ["Rider"] });
  const res = await request(app).get("/api/courier-requests/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].senderId, sender.id);
});

test("GET /api/courier-requests/mine rejects a Driver caller (Rider-only endpoint)", async () => {
  const token = mockAuthAs({ sub: "driver-sub-mine-1", groups: ["Driver"] });
  const res = await request(app).get("/api/courier-requests/mine").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("POST /api/courier-requests: two truly concurrent requests from the same sender — the database-level partial unique index rejects the loser", async () => {
  await createRider("rider-sub-courier-dup-race");
  const token = mockAuthAs({ sub: "rider-sub-courier-dup-race", groups: ["Rider"] });
  const payload = {
    pickupAddress: "A",
    dropoffAddress: "B",
    packageDescription: "Box",
    recipientName: "R",
    recipientPhone: "+1",
    estimatedFare: 15,
  };

  // Exercises CourierRequest_senderId_open_unique (added in migration
  // 20260823083433_add_open_request_unique_indexes) — the database-level
  // backstop behind the application-level `openRequest` pre-check, which
  // can't fully close a true concurrent double-submit on its own.
  const [a, b] = await Promise.all([
    request(app).post("/api/courier-requests").set("Authorization", `Bearer ${token}`).send(payload),
    request(app).post("/api/courier-requests").set("Authorization", `Bearer ${token}`).send(payload),
  ]);

  const statuses = [a.status, b.status].sort();
  assert.deepEqual(statuses, [201, 409]);

  const sender = await prisma.user.findUniqueOrThrow({ where: { cognitoSub: "rider-sub-courier-dup-race" } });
  const requests = await prisma.courierRequest.findMany({ where: { senderId: sender.id } });
  assert.equal(requests.length, 1, "exactly one CourierRequest row must exist, even under a true race");
});
