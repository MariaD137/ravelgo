import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAddToGroup } from "../test/helpers";
import { getLatestDriverLocation, resetRealtimeState } from "../realtime/hub";

beforeEach(() => {
  resetRealtimeState();
  return resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// P0 #2 — server-authoritative driver onboarding. The Driver role is granted
// by the SERVER (Cognito AdminAddUserToGroup), never self-assigned by a client.

test("POST /api/drivers/apply lets any authenticated user apply and grants the Driver group server-side", async () => {
  // A plain signed-up user — only in the Rider group, NOT already a Driver.
  const token = mockAuthAs({ sub: "applicant-1", groups: ["Rider"] });
  const addToGroup = mockCognitoAddToGroup();

  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Ada", lastName: "N", email: "ada@example.com" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  // The role grant went through the SERVER, with the caller's sub + Driver group.
  assert.equal(addToGroup.mock.callCount(), 1);
  assert.deepEqual(addToGroup.mock.calls[0].arguments, ["applicant-1", "Driver"]);

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: "applicant-1" } } });
  assert.ok(driver);
});

test("POST /api/drivers/apply requires authentication", async () => {
  const res = await request(app)
    .post("/api/drivers/apply")
    .send({ firstName: "No", lastName: "Auth", email: "noauth@example.com" });
  assert.equal(res.status, 401);
});

test("POST /api/drivers/apply is idempotent — re-applying returns the existing profile, no duplicate", async () => {
  const token = mockAuthAs({ sub: "applicant-2", groups: ["Rider"] });
  mockCognitoAddToGroup();

  const first = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Rex", lastName: "T", email: "rex@example.com" });
  assert.equal(first.status, 201);

  const second = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Rex", lastName: "T", email: "rex@example.com" });
  assert.equal(second.status, 200);
  assert.equal(second.body.id, first.body.id);

  const count = await prisma.driver.count({ where: { user: { cognitoSub: "applicant-2" } } });
  assert.equal(count, 1);
});

test("POST /api/drivers/apply does NOT report success when the Cognito group grant fails", async () => {
  const token = mockAuthAs({ sub: "applicant-3", groups: ["Rider"] });
  mockCognitoAddToGroup({ shouldThrow: true });

  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Fai", lastName: "L", email: "fail@example.com" });

  // The role never took effect, so the caller must not be told it worked.
  assert.equal(res.status, 502);
});

test("POST /api/drivers/apply is server-authoritative — a rider cannot reach Driver-only routes without it", async () => {
  // Before applying, a Rider-group token is rejected by a Driver-only route.
  const token = mockAuthAs({ sub: "applicant-4", groups: ["Rider"] });
  const blocked = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(blocked.status, 403);
});

test("POST /api/drivers/me creates a user + driver profile together", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Kay", lastName: "D", email: "kay@example.com" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  const user = await prisma.user.findUnique({ where: { cognitoSub: "driver-sub-1" } });
  assert.ok(user);
  assert.equal(user?.role, "DRIVER");
});

test("GET /api/drivers/me 404s before a driver profile exists", async () => {
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/drivers rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/drivers/:id/status lets an Admin suspend a driver", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-4", role: "DRIVER", firstName: "Lo", lastName: "P", email: "lo@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "SUSPENDED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "SUSPENDED");
});

test("PATCH /api/drivers/:id/status rejects a Support Agent admin preset", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-5", role: "DRIVER", firstName: "Mo", lastName: "P", email: "mo@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  await prisma.user.create({
    data: { cognitoSub: "support-agent-2", role: "ADMIN", firstName: "S", lastName: "A", email: "sa2@example.com", adminRole: "SUPPORT_AGENT" },
  });
  const token = mockAuthAs({ sub: "support-agent-2", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "SUSPENDED" });

  assert.equal(res.status, 403);
});

test("PATCH /api/drivers/me/availability lets an ACTIVE driver go online, blocks a pending one", async () => {
  // A pending driver cannot go online.
  const pendingUser = await prisma.user.create({
    data: { cognitoSub: "drv-pending", role: "DRIVER", firstName: "P", lastName: "D", email: "pd@example.com" },
  });
  await prisma.driver.create({ data: { userId: pendingUser.id, status: "PENDING_REVIEW" } });
  const pendingToken = mockAuthAs({ sub: "drv-pending", groups: ["Driver"] });
  const blocked = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${pendingToken}`)
    .send({ isOnline: true });
  assert.equal(blocked.status, 409);

  restoreAuth();

  // An approved (ACTIVE) driver can toggle online.
  const activeUser = await prisma.user.create({
    data: { cognitoSub: "drv-active", role: "DRIVER", firstName: "A", lastName: "D", email: "ad@example.com" },
  });
  await prisma.driver.create({ data: { userId: activeUser.id, status: "ACTIVE" } });
  const activeToken = mockAuthAs({ sub: "drv-active", groups: ["Driver"] });
  const ok = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${activeToken}`)
    .send({ isOnline: true });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.isOnline, true);
});

test("POST /api/drivers/me/location records the driver's position in the realtime hub (backs the admin Live Map)", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-loc-1", role: "DRIVER", firstName: "L", lastName: "D", email: "ld@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", isOnline: true } });
  const token = mockAuthAs({ sub: "drv-loc-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/drivers/me/location")
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5244, lng: 3.3792 });

  assert.equal(res.status, 200);
  assert.equal(res.body.driverId, driver.id);
  const stored = getLatestDriverLocation(driver.id);
  assert.equal(stored?.lat, 6.5244);
  assert.equal(stored?.lng, 3.3792);
});

test("GET /api/drivers/:driverId/documents/:documentId/url returns a signed URL for an Admin", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-1", role: "DRIVER", firstName: "D", lastName: "V", email: "dv1@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-1/license.pdf" },
  });

  const token = mockAuthAs({ sub: "admin-doc-1", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.ok(typeof res.body.url === "string" && res.body.url.startsWith("http"));
  assert.equal(res.body.expiresIn, 300);

  const audit = await prisma.auditLog.findFirst({ where: { entityId: doc.id, action: "DOCUMENT_VIEWED" } });
  assert.ok(audit, "expected a DOCUMENT_VIEWED audit entry");
});

test("GET /api/drivers/:driverId/documents/:documentId/url rejects a non-Admin caller", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-2", role: "DRIVER", firstName: "D", lastName: "V", email: "dv2@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-2/license.pdf" },
  });

  const token = mockAuthAs({ sub: "drv-doc-2", groups: ["Driver"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});

test("GET /api/drivers/:driverId/documents/:documentId/url rejects an admin whose role lacks drivers:write", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-3", role: "DRIVER", firstName: "D", lastName: "V", email: "dv3@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-3/license.pdf" },
  });
  await prisma.user.create({
    data: {
      cognitoSub: "finance-doc-url",
      role: "ADMIN",
      adminRole: "FINANCE_VIEWER",
      firstName: "F",
      lastName: "V",
      email: "fv-doc-url@example.com",
    },
  });

  const token = mockAuthAs({ sub: "finance-doc-url", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s for a driver that doesn't exist", async () => {
  const token = mockAuthAs({ sub: "admin-doc-2", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/does-not-exist/documents/also-missing/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s for a document that doesn't exist", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-4", role: "DRIVER", firstName: "D", lastName: "V", email: "dv4@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-doc-3", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/does-not-exist/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s when the document belongs to a different driver", async () => {
  const userA = await prisma.user.create({
    data: { cognitoSub: "drv-doc-5a", role: "DRIVER", firstName: "A", lastName: "V", email: "dv5a@example.com" },
  });
  const driverA = await prisma.driver.create({ data: { userId: userA.id } });
  const userB = await prisma.user.create({
    data: { cognitoSub: "drv-doc-5b", role: "DRIVER", firstName: "B", lastName: "V", email: "dv5b@example.com" },
  });
  const driverB = await prisma.driver.create({ data: { userId: userB.id } });
  const docB = await prisma.driverDocument.create({
    data: { driverId: driverB.id, title: "License", fileKey: "drv-doc-5b/license.pdf" },
  });

  const token = mockAuthAs({ sub: "admin-doc-4", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driverA.id}/documents/${docB.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s when the document has no fileKey uploaded yet", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-6", role: "DRIVER", firstName: "D", lastName: "V", email: "dv6@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", status: "NOT_UPLOADED" },
  });

  const token = mockAuthAs({ sub: "admin-doc-5", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:id includes the driver's phoneNumber (or null) for the admin detail view", async () => {
  const user = await prisma.user.create({
    data: {
      cognitoSub: "drv-phone-1",
      role: "DRIVER",
      firstName: "P",
      lastName: "H",
      email: "ph1@example.com",
      phoneNumber: "+2348012345678",
    },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-doc-6", groups: ["Admin"] });
  const res = await request(app).get(`/api/drivers/${driver.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.user.phoneNumber, "+2348012345678");
});

test("POST /api/drivers/me/location rejects an out-of-range coordinate", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-loc-2", role: "DRIVER", firstName: "L", lastName: "D", email: "ld2@example.com" },
  });
  await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
  const token = mockAuthAs({ sub: "drv-loc-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/drivers/me/location")
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 999, lng: 3.3792 });

  assert.equal(res.status, 400);
});
