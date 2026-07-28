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
