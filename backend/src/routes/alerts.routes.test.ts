import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAdminUserStatus } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("POST /api/emergency-alerts lets any authenticated user raise an SOS", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/emergency-alerts")
    .set("Authorization", `Bearer ${token}`)
    .send({ type: "SOS", message: "Driver is going the wrong way" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "OPEN");
});

test("GET /api/emergency-alerts/mine only returns the caller's own alerts", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "rider-sub-2", role: "RIDER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const other = await prisma.user.create({
    data: { cognitoSub: "rider-sub-3", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  await prisma.emergencyAlert.create({ data: { userId: me.id, type: "SOS" } });
  await prisma.emergencyAlert.create({ data: { userId: other.id, type: "FRAUD_SUSPECTED" } });

  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const res = await request(app).get("/api/emergency-alerts/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
});

test("GET /api/emergency-alerts rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const res = await request(app).get("/api/emergency-alerts").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/emergency-alerts/:id/status lets an Admin resolve an alert and stamps resolvedAt", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "rider-sub-5", role: "RIDER", firstName: "G", lastName: "H", email: "g@example.com" },
  });
  const alert = await prisma.emergencyAlert.create({ data: { userId: user.id, type: "SOS" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch(`/api/emergency-alerts/${alert.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "RESOLVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "RESOLVED");
  assert.ok(res.body.resolvedAt);
});

test("PATCH /api/emergency-alerts/:id/status lets a Support Agent admin preset resolve an alert", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "rider-sub-6", role: "RIDER", firstName: "I", lastName: "J", email: "ij@example.com" },
  });
  const alert = await prisma.emergencyAlert.create({ data: { userId: user.id, type: "SOS" } });
  await prisma.user.create({
    data: { cognitoSub: "support-agent-3", role: "ADMIN", firstName: "S", lastName: "A", email: "sa3@example.com", adminRole: "SUPPORT_AGENT" },
  });
  const token = mockAuthAs({ sub: "support-agent-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const res = await request(app)
    .patch(`/api/emergency-alerts/${alert.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "RESOLVED" });

  assert.equal(res.status, 200);
});

test("PATCH /api/emergency-alerts/:id/status rejects a Finance Viewer admin preset", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "rider-sub-7", role: "RIDER", firstName: "K", lastName: "L", email: "kl@example.com" },
  });
  const alert = await prisma.emergencyAlert.create({ data: { userId: user.id, type: "SOS" } });
  await prisma.user.create({
    data: { cognitoSub: "finance-viewer-3", role: "ADMIN", firstName: "F", lastName: "V", email: "fv3@example.com", adminRole: "FINANCE_VIEWER" },
  });
  const token = mockAuthAs({ sub: "finance-viewer-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const res = await request(app)
    .patch(`/api/emergency-alerts/${alert.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "RESOLVED" });

  assert.equal(res.status, 403);
});
