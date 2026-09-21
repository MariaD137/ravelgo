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

// The Driver App maps each of these to a different message — they must stay
// distinguishable at the HTTP level: no token vs. a non-driver token vs. a
// driver token with no profile row vs. a real driver.
test("GET /api/documents/me distinguishes unauthenticated (401), non-driver (403), no profile (404) and driver (200)", async () => {
  const anonymous = await request(app).get("/api/documents/me");
  assert.equal(anonymous.status, 401);

  const riderToken = mockAuthAs({ sub: "docs-rider-sub", groups: ["Rider"] });
  const rider = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(rider.status, 403);

  // In the Driver group (server granted it) but the profile row is missing.
  const orphanToken = mockAuthAs({ sub: "docs-orphan-sub", groups: ["Driver"] });
  const orphan = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${orphanToken}`);
  assert.equal(orphan.status, 404);

  const user = await prisma.user.create({
    data: { cognitoSub: "docs-driver-sub", role: "DRIVER", firstName: "D", lastName: "R", email: "docs-driver@example.com" },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  const driverToken = mockAuthAs({ sub: "docs-driver-sub", groups: ["Driver"] });
  const driver = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(driver.status, 200);
  assert.deepEqual(driver.body, []);
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

// --- GET /documents/:id/url: driver self-service signed URL ----------------

test("GET /api/documents/:id/url returns a signed URL for the document's own driver", async () => {
  await createDriver("driver-self-1");
  const driver = await prisma.driver.findFirstOrThrow({ where: { user: { cognitoSub: "driver-self-1" } } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "driver-self-1/license.pdf" },
  });

  const token = mockAuthAs({ sub: "driver-self-1", groups: ["Driver"] });
  const res = await request(app).get(`/api/documents/${doc.id}/url`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.ok(typeof res.body.url === "string" && res.body.url.startsWith("http"));
  assert.equal(res.body.expiresIn, 300);
});

test("GET /api/documents/:id/url 404s when the document belongs to a different driver (cross-driver access denied)", async () => {
  await createDriver("driver-self-2a");
  await createDriver("driver-self-2b");
  const driverB = await prisma.driver.findFirstOrThrow({ where: { user: { cognitoSub: "driver-self-2b" } } });
  const docB = await prisma.driverDocument.create({
    data: { driverId: driverB.id, title: "License", fileKey: "driver-self-2b/license.pdf" },
  });

  const tokenA = mockAuthAs({ sub: "driver-self-2a", groups: ["Driver"] });
  const res = await request(app).get(`/api/documents/${docB.id}/url`).set("Authorization", `Bearer ${tokenA}`);

  assert.equal(res.status, 404);
});

test("GET /api/documents/:id/url 404s for a document that doesn't exist", async () => {
  await createDriver("driver-self-3");
  const token = mockAuthAs({ sub: "driver-self-3", groups: ["Driver"] });
  const res = await request(app).get(`/api/documents/does-not-exist/url`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/documents/:id/url 404s when the document has no fileKey uploaded yet", async () => {
  await createDriver("driver-self-4");
  const driver = await prisma.driver.findFirstOrThrow({ where: { user: { cognitoSub: "driver-self-4" } } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", status: "NOT_UPLOADED" },
  });

  const token = mockAuthAs({ sub: "driver-self-4", groups: ["Driver"] });
  const res = await request(app).get(`/api/documents/${doc.id}/url`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/documents/:id/url rejects a non-Driver caller", async () => {
  await createDriver("driver-self-5");
  const driver = await prisma.driver.findFirstOrThrow({ where: { user: { cognitoSub: "driver-self-5" } } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "driver-self-5/license.pdf" },
  });

  const token = mockAuthAs({ sub: "rider-self-5", groups: ["Rider"] });
  const res = await request(app).get(`/api/documents/${doc.id}/url`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
