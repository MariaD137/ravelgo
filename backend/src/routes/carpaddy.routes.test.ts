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

async function createDriver(cognitoSub: string, status: "PENDING_REVIEW" | "ACTIVE" = "ACTIVE") {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id, status } });
}

test("POST /api/car-paddy submits a request for the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/car-paddy")
    .set("Authorization", `Bearer ${token}`)
    .send({ plateNumber: "XYZ-999" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "SUBMITTED");
});

test("POST /api/car-paddy rejects a driver pending admin approval", async () => {
  await createDriver("driver-sub-1b", "PENDING_REVIEW");
  const token = mockAuthAs({ sub: "driver-sub-1b", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/car-paddy")
    .set("Authorization", `Bearer ${token}`)
    .send({ plateNumber: "XYZ-999" });

  assert.equal(res.status, 409);
});

test("GET /api/car-paddy rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/car-paddy").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/car-paddy/:id lets an Admin approve and stamps reviewedAt", async () => {
  const driver = await createDriver("driver-sub-3");
  const req = await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "AAA-1" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");
  assert.ok(res.body.reviewedAt);
});

test("PATCH /api/car-paddy/:id rejects a Support Agent admin and records an audit entry on success", async () => {
  const driver = await createDriver("driver-sub-4");
  const req = await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "BBB-2" } });
  await prisma.user.create({
    data: { cognitoSub: "support-carpaddy", role: "ADMIN", adminRole: "SUPPORT_AGENT", firstName: "S", lastName: "A", email: "sa-carpaddy@example.com" },
  });

  const supportToken = mockAuthAs({ sub: "support-carpaddy", groups: ["Admin"] });
  const denied = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${supportToken}`)
    .send({ status: "APPROVED" });
  assert.equal(denied.status, 403);

  restoreAuth();
  const superToken = mockAuthAs({ sub: "super-carpaddy", groups: ["Admin"] });
  const approved = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${superToken}`)
    .send({ status: "APPROVED" });
  assert.equal(approved.status, 200);

  const audit = await prisma.auditLog.findFirst({ where: { action: "CAR_PADDY_REQUEST_REVIEWED", entityId: req.id } });
  assert.ok(audit);
});

test("POST /api/car-paddy accepts a renewalDate and an owned fileKey", async () => {
  await createDriver("driver-sub-evidence-1");
  const token = mockAuthAs({ sub: "driver-sub-evidence-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/car-paddy")
    .set("Authorization", `Bearer ${token}`)
    .send({
      plateNumber: "EVD-001",
      renewalDate: "2027-01-15",
      fileKey: "driver-sub-evidence-1/renewal-receipt.pdf",
    });

  assert.equal(res.status, 201);
  assert.ok(res.body.renewalDate);
  assert.equal(res.body.fileKey, "driver-sub-evidence-1/renewal-receipt.pdf");
});

test("POST /api/car-paddy rejects a fileKey that doesn't belong to the caller", async () => {
  await createDriver("driver-sub-evidence-2");
  const token = mockAuthAs({ sub: "driver-sub-evidence-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/car-paddy")
    .set("Authorization", `Bearer ${token}`)
    .send({ plateNumber: "EVD-002", fileKey: "someone-elses-sub/renewal.pdf" });

  assert.equal(res.status, 403);
});

test("GET /api/car-paddy/:id/document-url returns a signed URL for an Admin, 404s with no document, and 403s a non-Admin", async () => {
  const driver = await createDriver("driver-sub-evidence-3");
  const withDoc = await prisma.carPaddyRequest.create({
    data: { driverId: driver.id, plateNumber: "EVD-003", fileKey: "driver-sub-evidence-3/renewal.pdf" },
  });
  const withoutDoc = await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "EVD-004" } });

  const adminToken = mockAuthAs({ sub: "admin-sub-evidence-1", groups: ["Admin"] });
  const signed = await request(app)
    .get(`/api/car-paddy/${withDoc.id}/document-url`)
    .set("Authorization", `Bearer ${adminToken}`);
  assert.equal(signed.status, 200);
  assert.ok(typeof signed.body.url === "string" && signed.body.url.startsWith("http"));
  assert.equal(signed.body.expiresIn, 300);

  const noDoc = await request(app)
    .get(`/api/car-paddy/${withoutDoc.id}/document-url`)
    .set("Authorization", `Bearer ${adminToken}`);
  assert.equal(noDoc.status, 404);

  restoreAuth();
  const driverToken = mockAuthAs({ sub: "driver-sub-evidence-3", groups: ["Driver"] });
  const denied = await request(app)
    .get(`/api/car-paddy/${withDoc.id}/document-url`)
    .set("Authorization", `Bearer ${driverToken}`);
  assert.equal(denied.status, 403);
});

test("PATCH /api/car-paddy/:id requires a reason to reject, stores/clears it, and notifies the driver", async () => {
  const driver = await createDriver("driver-sub-evidence-4");
  const req = await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "EVD-005" } });
  const token = mockAuthAs({ sub: "admin-sub-evidence-2", groups: ["Admin"] });

  const missingReason = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED" });
  assert.equal(missingReason.status, 400);

  const rejected = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED", rejectionReason: "Receipt does not match plate number" });
  assert.equal(rejected.status, 200);
  assert.equal(rejected.body.rejectionReason, "Receipt does not match plate number");

  const notifications = await prisma.notification.findMany({ where: { userId: driver.userId } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "CAR_PADDY_REQUEST_REVIEWED");

  const approved = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });
  assert.equal(approved.body.rejectionReason, null);
});
