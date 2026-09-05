import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import {
  mockAuthAs,
  restoreAuth,
  resetDb,
  mockCognitoCreateAdminUser,
  mockCognitoAddToGroup,
  mockCognitoSetUserEnabled,
} from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function seedAdmin(cognitoSub: string, email: string, adminRole: "SUPER_ADMIN" | "OPERATIONS_MANAGER" | "SUPPORT_AGENT" | "FINANCE_VIEWER" | null = null) {
  return prisma.user.create({
    data: { cognitoSub, role: "ADMIN", firstName: "Ad", lastName: "Min", email, adminRole },
  });
}

test("POST /api/admin-users rejects a caller without a Super Admin preset", async () => {
  await seedAdmin("ops-sub-1", "ops1@example.com", "OPERATIONS_MANAGER");
  const token = mockAuthAs({ sub: "ops-sub-1", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "new@example.com", firstName: "New", lastName: "Admin", adminRole: "SUPPORT_AGENT" });

  assert.equal(res.status, 403);
});

test("POST /api/admin-users lets an admin with no preset (legacy full access) invite a new restricted admin", async () => {
  // No Postgres User row at all for this sub — the same shape as every
  // pre-existing admin account before this preset system shipped.
  const token = mockAuthAs({ sub: "legacy-admin-1", groups: ["Admin"] });
  mockCognitoCreateAdminUser("cognito-new-user-1");
  mockCognitoAddToGroup();

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "support1@example.com", firstName: "Sup", lastName: "Port", adminRole: "SUPPORT_AGENT" });

  assert.equal(res.status, 201);
  assert.equal(res.body.email, "support1@example.com");
  assert.equal(res.body.adminRole, "SUPPORT_AGENT");

  const created = await prisma.user.findUnique({ where: { email: "support1@example.com" } });
  assert.equal(created?.cognitoSub, "cognito-new-user-1");
  assert.equal(created?.role, "ADMIN");

  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_CREATED" } });
  assert.equal(entry?.entityId, created?.id);
});

test("POST /api/admin-users rejects a duplicate email", async () => {
  await seedAdmin("super-sub-1", "dupe@example.com", "SUPER_ADMIN");
  const token = mockAuthAs({ sub: "super-sub-1", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "dupe@example.com", firstName: "X", lastName: "Y", adminRole: "FINANCE_VIEWER" });

  assert.equal(res.status, 409);
});

test("GET /api/admin-users lists admin users for a Super Admin and rejects a restricted preset", async () => {
  await seedAdmin("super-sub-2", "super2@example.com", "SUPER_ADMIN");
  await seedAdmin("finance-sub-1", "finance1@example.com", "FINANCE_VIEWER");

  const superToken = mockAuthAs({ sub: "super-sub-2", groups: ["Admin"] });
  const ok = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${superToken}`);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.length, 2);

  restoreAuth();
  const financeToken = mockAuthAs({ sub: "finance-sub-1", groups: ["Admin"] });
  const denied = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${financeToken}`);
  assert.equal(denied.status, 403);
});

test("PATCH /api/admin-users/:id/role blocks demoting the last Super Admin", async () => {
  const onlySuperAdmin = await seedAdmin("super-sub-3", "super3@example.com", "SUPER_ADMIN");
  const token = mockAuthAs({ sub: "super-sub-3", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/admin-users/${onlySuperAdmin.id}/role`)
    .set("Authorization", `Bearer ${token}`)
    .send({ adminRole: "OPERATIONS_MANAGER" });

  assert.equal(res.status, 409);
});

test("PATCH /api/admin-users/:id/role allows demoting a Super Admin when another one remains", async () => {
  const superA = await seedAdmin("super-sub-4", "super4@example.com", "SUPER_ADMIN");
  await seedAdmin("super-sub-5", "super5@example.com", "SUPER_ADMIN");
  const token = mockAuthAs({ sub: "super-sub-4", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/admin-users/${superA.id}/role`)
    .set("Authorization", `Bearer ${token}`)
    .send({ adminRole: "OPERATIONS_MANAGER" });

  assert.equal(res.status, 200);
  assert.equal(res.body.adminRole, "OPERATIONS_MANAGER");
});

test("PATCH /api/admin-users/:id/status suspends an admin and disables their Cognito account", async () => {
  const superA = await seedAdmin("super-sub-6", "super6@example.com", "SUPER_ADMIN");
  await seedAdmin("super-sub-7", "super7@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("ops-sub-2", "ops2@example.com", "OPERATIONS_MANAGER");
  const token = mockAuthAs({ sub: "super-sub-6", groups: ["Admin"] });
  const setEnabled = mockCognitoSetUserEnabled();

  const res = await request(app)
    .patch(`/api/admin-users/${target.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });

  assert.equal(res.status, 200);
  assert.equal(res.body.suspended, true);
  assert.equal(setEnabled.mock.calls.length, 1);
  void superA;
});

test("PATCH /api/admin-users/:id/status blocks suspending the last active Super Admin", async () => {
  const onlySuperAdmin = await seedAdmin("super-sub-8", "super8@example.com", "SUPER_ADMIN");
  const token = mockAuthAs({ sub: "super-sub-8", groups: ["Admin"] });
  mockCognitoSetUserEnabled();

  const res = await request(app)
    .patch(`/api/admin-users/${onlySuperAdmin.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });

  assert.equal(res.status, 409);
});
