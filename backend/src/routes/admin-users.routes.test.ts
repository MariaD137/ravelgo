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
  mockCognitoAdminUserStatus,
  mockCognitoResendAdminInvitation,
  mockCognitoAdminResetUserPassword,
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
  mockCognitoAdminUserStatus({ cognitoStatus: "FORCE_CHANGE_PASSWORD" });

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "support1@example.com", firstName: "Sup", lastName: "Port", adminRole: "SUPPORT_AGENT" });

  assert.equal(res.status, 201);
  assert.equal(res.body.email, "support1@example.com");
  assert.equal(res.body.adminRole, "SUPPORT_AGENT");
  assert.equal(res.body.status, "INVITED");
  assert.ok(!("password" in res.body));

  const created = await prisma.user.findUnique({ where: { email: "support1@example.com" } });
  assert.equal(created?.cognitoSub, "cognito-new-user-1");
  assert.equal(created?.role, "ADMIN");

  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_CREATED" } });
  assert.equal(entry?.entityId, created?.id);
});

test("POST /api/admin-users normalizes email case for the duplicate check", async () => {
  await seedAdmin("super-sub-norm", "already@Example.com".toLowerCase(), "SUPER_ADMIN");
  const token = mockAuthAs({ sub: "super-sub-norm", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "Already@EXAMPLE.com", firstName: "X", lastName: "Y", adminRole: "FINANCE_VIEWER" });

  assert.equal(res.status, 409);
});

test("POST /api/admin-users stores a lowercased, trimmed email", async () => {
  const token = mockAuthAs({ sub: "super-sub-norm-2", groups: ["Admin"] });
  mockCognitoCreateAdminUser("cognito-new-user-2");
  mockCognitoAddToGroup();
  mockCognitoAdminUserStatus({ cognitoStatus: "FORCE_CHANGE_PASSWORD" });

  const res = await request(app)
    .post("/api/admin-users")
    .set("Authorization", `Bearer ${token}`)
    .send({ email: "  Mixed.Case@Example.COM  ", firstName: "New", lastName: "Admin", adminRole: "SUPPORT_AGENT" });

  assert.equal(res.status, 201);
  assert.equal(res.body.email, "mixed.case@example.com");
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
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED", mfaEnabled: true });

  const superToken = mockAuthAs({ sub: "super-sub-2", groups: ["Admin"] });
  const ok = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${superToken}`);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.length, 2);
  assert.equal(ok.body[0].status, "ACTIVE");
  assert.equal(ok.body[0].mfaEnabled, true);

  restoreAuth();
  const financeToken = mockAuthAs({ sub: "finance-sub-1", groups: ["Admin"] });
  const denied = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${financeToken}`);
  assert.equal(denied.status, 403);
});

test("GET /api/admin-users/:id returns one admin's detail", async () => {
  await seedAdmin("super-sub-detail", "super-detail@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("ops-sub-detail", "ops-detail@example.com", "OPERATIONS_MANAGER");
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED", mfaEnabled: false });
  const token = mockAuthAs({ sub: "super-sub-detail", groups: ["Admin"] });

  const res = await request(app).get(`/api/admin-users/${target.id}`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.email, "ops-detail@example.com");
  assert.equal(res.body.status, "ACTIVE");
  assert.equal(res.body.mfaEnabled, false);
});

test("GET /api/admin-users/:id 404s for a non-admin user id", async () => {
  const superAdmin = await seedAdmin("super-sub-detail-2", "super-detail-2@example.com", "SUPER_ADMIN");
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "R", lastName: "I", email: "rider1@example.com" },
  });
  void superAdmin;
  const token = mockAuthAs({ sub: "super-sub-detail-2", groups: ["Admin"] });

  const res = await request(app).get(`/api/admin-users/${rider.id}`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/admin-users/me returns the caller's own profile", async () => {
  await seedAdmin("ops-sub-me", "ops-me@example.com", "OPERATIONS_MANAGER");
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED", mfaEnabled: true });
  const token = mockAuthAs({ sub: "ops-sub-me", groups: ["Admin"] });

  const res = await request(app).get("/api/admin-users/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.email, "ops-me@example.com");
  assert.equal(res.body.adminRole, "OPERATIONS_MANAGER");
  assert.equal(res.body.mfaEnabled, true);
});

test("GET /api/admin-users/me falls back to token claims for a legacy admin with no User row", async () => {
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED", mfaEnabled: false });
  const token = mockAuthAs({ sub: "legacy-admin-me", email: "legacy@example.com", groups: ["Admin"] });

  const res = await request(app).get("/api/admin-users/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.email, "legacy@example.com");
  assert.equal(res.body.adminRole, "SUPER_ADMIN");
});

test("GET /api/admin-users/me rejects a non-admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-me", groups: ["Rider"] });
  const res = await request(app).get("/api/admin-users/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("POST /api/admin-users/me/mfa-enrolled records an audit entry for the caller", async () => {
  const me = await seedAdmin("ops-sub-mfa", "ops-mfa@example.com", "OPERATIONS_MANAGER");
  const token = mockAuthAs({ sub: "ops-sub-mfa", groups: ["Admin"] });

  const res = await request(app).post("/api/admin-users/me/mfa-enrolled").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 204);

  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_MFA_ENABLED" } });
  assert.equal(entry?.entityId, me.id);
  assert.equal(entry?.actorSub, "ops-sub-mfa");
});

test("POST /api/admin-users/:id/resend-invitation resends while the admin hasn't signed in yet", async () => {
  await seedAdmin("super-sub-resend", "super-resend@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("invited-sub-1", "invited1@example.com", "SUPPORT_AGENT");
  mockCognitoAdminUserStatus({ cognitoStatus: "FORCE_CHANGE_PASSWORD" });
  const resend = mockCognitoResendAdminInvitation();
  const token = mockAuthAs({ sub: "super-sub-resend", groups: ["Admin"] });

  const res = await request(app)
    .post(`/api/admin-users/${target.id}/resend-invitation`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(resend.mock.calls.length, 1);
  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_INVITATION_RESENT" } });
  assert.equal(entry?.entityId, target.id);
});

test("POST /api/admin-users/:id/resend-invitation rejects an admin who already signed in", async () => {
  await seedAdmin("super-sub-resend-2", "super-resend-2@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("active-sub-1", "active1@example.com", "SUPPORT_AGENT");
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
  const resend = mockCognitoResendAdminInvitation();
  const token = mockAuthAs({ sub: "super-sub-resend-2", groups: ["Admin"] });

  const res = await request(app)
    .post(`/api/admin-users/${target.id}/resend-invitation`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  assert.equal(resend.mock.calls.length, 0);
});

test("POST /api/admin-users/:id/password-reset triggers a Cognito reset and never returns a password", async () => {
  await seedAdmin("super-sub-reset", "super-reset@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("target-sub-reset", "target-reset@example.com", "SUPPORT_AGENT");
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
  const reset = mockCognitoAdminResetUserPassword();
  const token = mockAuthAs({ sub: "super-sub-reset", groups: ["Admin"] });

  const res = await request(app)
    .post(`/api/admin-users/${target.id}/password-reset`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(reset.mock.calls.length, 1);
  assert.ok(!JSON.stringify(res.body).toLowerCase().includes("password"));
  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_PASSWORD_RESET_REQUESTED" } });
  assert.equal(entry?.entityId, target.id);
});

test("POST /api/admin-users/:id/password-reset rejects a caller without manage_admins", async () => {
  const target = await seedAdmin("target-sub-reset-2", "target-reset-2@example.com", "SUPPORT_AGENT");
  const token = mockAuthAs({ sub: "ops-sub-reset-denied", groups: ["Admin"] });
  await seedAdmin("ops-sub-reset-denied", "ops-reset-denied@example.com", "OPERATIONS_MANAGER");

  const res = await request(app)
    .post(`/api/admin-users/${target.id}/password-reset`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
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
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
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
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
  const token = mockAuthAs({ sub: "super-sub-6", groups: ["Admin"] });
  const setEnabled = mockCognitoSetUserEnabled();

  const res = await request(app)
    .patch(`/api/admin-users/${target.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });

  assert.equal(res.status, 200);
  assert.equal(res.body.suspended, true);
  assert.equal(res.body.status, "SUSPENDED");
  assert.equal(setEnabled.mock.calls.length, 1);
  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_DISABLED" } });
  assert.equal(entry?.entityId, target.id);
  void superA;
});

test("PATCH /api/admin-users/:id/status blocks an admin from suspending their own account", async () => {
  await seedAdmin("super-sub-self", "super-self@example.com", "SUPER_ADMIN");
  await seedAdmin("super-sub-self-2", "super-self-2@example.com", "SUPER_ADMIN");
  const self = await prisma.user.findUniqueOrThrow({ where: { cognitoSub: "super-sub-self" } });
  const token = mockAuthAs({ sub: "super-sub-self", groups: ["Admin"] });
  mockCognitoSetUserEnabled();

  const res = await request(app)
    .patch(`/api/admin-users/${self.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });

  assert.equal(res.status, 400);
  const unchanged = await prisma.user.findUnique({ where: { id: self.id } });
  assert.equal(unchanged?.suspended, false);
});

test("PATCH /api/admin-users/:id/status reinstates a suspended admin", async () => {
  await seedAdmin("super-sub-9", "super9@example.com", "SUPER_ADMIN");
  const target = await seedAdmin("ops-sub-3", "ops3@example.com", "OPERATIONS_MANAGER");
  await prisma.user.update({ where: { id: target.id }, data: { suspended: true } });
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
  const setEnabled = mockCognitoSetUserEnabled();
  const token = mockAuthAs({ sub: "super-sub-9", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/admin-users/${target.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: false });

  assert.equal(res.status, 200);
  assert.equal(res.body.suspended, false);
  assert.equal(setEnabled.mock.calls.length, 1);
  const entry = await prisma.auditLog.findFirst({ where: { action: "ADMIN_USER_ENABLED" } });
  assert.equal(entry?.entityId, target.id);
});

test("a suspended admin's still-valid access token loses protected access immediately", async () => {
  // Simulates the real-world gap this closes: AdminDisableUser only blocks
  // Cognito from *issuing new* tokens, so a token minted before the
  // suspension stays cryptographically valid for up to its full lifetime.
  // Postgres suspended=true must reject it anyway, without waiting for the
  // Cognito-side token to expire on its own.
  const suspended = await seedAdmin("suspended-sub-1", "suspended1@example.com", "SUPER_ADMIN");
  await seedAdmin("super-sub-other", "super-other@example.com", "SUPER_ADMIN");
  await prisma.user.update({ where: { id: suspended.id }, data: { suspended: true } });
  const token = mockAuthAs({ sub: "suspended-sub-1", groups: ["Admin"] });

  const res = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("re-enabling an admin restores their protected access", async () => {
  const target = await seedAdmin("was-suspended-sub-1", "was-suspended1@example.com", "SUPER_ADMIN");
  await seedAdmin("super-sub-reenable", "super-reenable@example.com", "SUPER_ADMIN");
  await prisma.user.update({ where: { id: target.id }, data: { suspended: true } });
  await prisma.user.update({ where: { id: target.id }, data: { suspended: false } });
  mockCognitoAdminUserStatus({ cognitoStatus: "CONFIRMED" });
  const token = mockAuthAs({ sub: "was-suspended-sub-1", groups: ["Admin"] });

  const res = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});
