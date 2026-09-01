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
