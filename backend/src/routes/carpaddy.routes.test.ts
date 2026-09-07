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
