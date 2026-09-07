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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id } });
}

test("POST /api/documents registers a document as PENDING for the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    .send({ title: "Driver's license", fileKey: "driver-sub-1/abc-license.pdf" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING");
});

test("POST /api/documents rejects a fileKey that doesn't belong to the calling user", async () => {
  await createDriver("driver-sub-9");
  const token = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    // Someone else's (or a fabricated) prefix.
    .send({ title: "License", fileKey: "driver-sub-someone-else/abc-license.pdf" });

  assert.equal(res.status, 403);
  const stored = await prisma.driverDocument.findMany();
  assert.equal(stored.length, 0);
});

test("GET /api/documents/me only returns the calling driver's own documents", async () => {
  const driverA = await createDriver("driver-sub-2");
  const driverB = await createDriver("driver-sub-3");
  await prisma.driverDocument.create({ data: { driverId: driverA.id, title: "Mine", fileKey: "k1" } });
  await prisma.driverDocument.create({ data: { driverId: driverB.id, title: "Not mine", fileKey: "k2" } });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].title, "Mine");
});

test("PATCH /api/documents/:id/review rejects a non-Admin caller", async () => {
  const driver = await createDriver("driver-sub-4");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k3" } });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});

test("PATCH /api/documents/:id/review lets an Admin approve a document", async () => {
  const driver = await createDriver("driver-sub-5");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k4" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");
  assert.equal(res.body.rejectionReason, null);
});

test("PATCH /api/documents/:id/review rejects a REJECTED status with no rejectionReason", async () => {
  const driver = await createDriver("driver-sub-6");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k5" } });

  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED" });

  assert.equal(res.status, 400);
  const stored = await prisma.driverDocument.findUnique({ where: { id: doc.id } });
  assert.equal(stored?.status, "NOT_UPLOADED");
});

test("PATCH /api/documents/:id/review rejects a REJECTED status with a blank rejectionReason", async () => {
  const driver = await createDriver("driver-sub-7");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k6" } });

  const token = mockAuthAs({ sub: "admin-sub-3", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED", rejectionReason: "   " });

  assert.equal(res.status, 400);
});

test("PATCH /api/documents/:id/review persists and returns the rejectionReason", async () => {
  const driver = await createDriver("driver-sub-8");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k7" } });

  const token = mockAuthAs({ sub: "admin-sub-4", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED", rejectionReason: "Photo is blurry, please retake it." });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "REJECTED");
  assert.equal(res.body.rejectionReason, "Photo is blurry, please retake it.");

  const audit = await prisma.auditLog.findFirst({ where: { entityId: doc.id, action: "DOCUMENT_REJECTED" } });
  assert.ok(audit, "expected a DOCUMENT_REJECTED audit entry");
});

test("PATCH /api/documents/:id/review clears a prior rejectionReason on approval", async () => {
  const driver = await createDriver("driver-sub-10");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "Doc", fileKey: "k8", status: "REJECTED", rejectionReason: "Old reason" },
  });

  const token = mockAuthAs({ sub: "admin-sub-5", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.rejectionReason, null);
});

test("PATCH /api/documents/:id/review returns 404 for a document that doesn't exist", async () => {
  const token = mockAuthAs({ sub: "admin-sub-6", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/does-not-exist/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 404);
});

test("PATCH /api/documents/:id/review rejects an admin whose role lacks drivers:write", async () => {
  const driver = await createDriver("driver-sub-11");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k9" } });
  await prisma.user.create({
    data: {
      cognitoSub: "finance-docs",
      role: "ADMIN",
      adminRole: "FINANCE_VIEWER",
      firstName: "F",
      lastName: "V",
      email: "fv-docs@example.com",
    },
  });

  const token = mockAuthAs({ sub: "finance-docs", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});
