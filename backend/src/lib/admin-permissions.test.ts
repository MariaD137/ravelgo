import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import express from "express";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireActiveAdmin } from "./admin-permissions";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// A throwaway app exercising requireActiveAdmin directly, same convention as
// middleware/rate-limit.test.ts — proves the middleware's own contract in
// isolation, in addition to the end-to-end route tests below.
function throwawayApp() {
  const a = express();
  a.get("/protected", requireAuth, requireActiveAdmin, (_req, res) => res.json({ ok: true }));
  return a;
}

test("requireActiveAdmin: an active admin (no Postgres User row — legacy SUPER_ADMIN) can read", async () => {
  const token = mockAuthAs({ sub: "active-admin-no-row", groups: ["Admin"] });
  const res = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});

test("requireActiveAdmin: an active admin with a Postgres User row can read", async () => {
  await prisma.user.create({
    data: { cognitoSub: "active-admin-with-row", role: "ADMIN", firstName: "A", lastName: "A", email: "active@example.com" },
  });
  const token = mockAuthAs({ sub: "active-admin-with-row", groups: ["Admin"] });
  const res = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});

test("requireActiveAdmin: a suspended admin cannot read, even though they still carry the Cognito Admin group", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "suspended-admin-1",
      role: "ADMIN",
      suspended: true,
      firstName: "S",
      lastName: "A",
      email: "suspended1@example.com",
    },
  });
  // The Cognito token itself is still cryptographically valid (this is
  // exactly the scenario being closed: AdminDisableUser blocks issuing new
  // tokens, not the one already issued) — mockAuthAs simulates that by
  // returning "Admin" in groups regardless of the Postgres suspended flag.
  const token = mockAuthAs({ sub: "suspended-admin-1", groups: ["Admin"] });
  const res = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
  assert.equal(res.body.error, "This admin account is suspended");
});

test("requireActiveAdmin: a non-Admin caller (Driver/Rider group) cannot read", async () => {
  const driverToken = mockAuthAs({ sub: "driver-not-admin", groups: ["Driver"] });
  const driverRes = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(driverRes.status, 403);
  assert.equal(driverRes.body.error, "Insufficient permissions");

  restoreAuth();
  const riderToken = mockAuthAs({ sub: "rider-not-admin", groups: ["Rider"] });
  const riderRes = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(riderRes.status, 403);
});

test("requireActiveAdmin: a Super Admin (explicit adminRole) can read, and reactivating a suspended admin restores read access", async () => {
  const user = await prisma.user.create({
    data: {
      cognitoSub: "super-admin-explicit",
      role: "ADMIN",
      adminRole: "SUPER_ADMIN",
      suspended: true,
      firstName: "S",
      lastName: "A",
      email: "super-explicit@example.com",
    },
  });
  const token = mockAuthAs({ sub: "super-admin-explicit", groups: ["Admin"] });

  const whileSuspended = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${token}`);
  assert.equal(whileSuspended.status, 403);

  await prisma.user.update({ where: { id: user.id }, data: { suspended: false } });
  const afterReactivation = await request(throwawayApp()).get("/protected").set("Authorization", `Bearer ${token}`);
  assert.equal(afterReactivation.status, 200);
});

// End-to-end proof against the real app, not just the isolated middleware —
// the exact scenario the audit's B2/J1 finding described: a just-suspended
// admin's still-valid token reading the dashboard/audit log/live map.
test("end-to-end: a suspended admin gets 403 from the real dashboard, audit log, live map and financial dashboard routes", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "suspended-admin-e2e",
      role: "ADMIN",
      suspended: true,
      firstName: "S",
      lastName: "A",
      email: "suspended-e2e@example.com",
    },
  });
  const token = mockAuthAs({ sub: "suspended-admin-e2e", groups: ["Admin"] });

  for (const path of ["/api/admin/dashboard", "/api/admin/audit", "/api/admin/live-map", "/api/admin/financial-dashboard"]) {
    const res = await request(app).get(path).set("Authorization", `Bearer ${token}`);
    assert.equal(res.status, 403, `${path} should reject a suspended admin`);
  }
});

test("end-to-end: an active admin still reads the real dashboard successfully", async () => {
  const token = mockAuthAs({ sub: "active-admin-e2e", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/dashboard").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.ok(typeof res.body.activeTrips === "number");
});
