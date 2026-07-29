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

test("GET /api/riders requires a bearer token", async () => {
  const res = await request(app).get("/api/riders");
  assert.equal(res.status, 401);
});

test("GET /api/riders rejects a caller without the Admin group", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app).get("/api/riders").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("GET /api/riders lists riders for an Admin caller", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "Ada", lastName: "L", email: "ada@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "driver-sub-1", role: "DRIVER", firstName: "Bob", lastName: "D", email: "bob@example.com" },
  });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app).get("/api/riders").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.page, 1);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].email, "ada@example.com");
});

test("POST /api/riders/me creates my profile on first call, then upserts on repeat calls", async () => {
  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const payload = { firstName: "Nia", lastName: "R", email: "nia@example.com" };

  const first = await request(app).post("/api/riders/me").set("Authorization", `Bearer ${token}`).send(payload);
  assert.equal(first.status, 201);
  assert.equal(first.body.cognitoSub, "rider-sub-2");

  const second = await request(app).post("/api/riders/me").set("Authorization", `Bearer ${token}`).send(payload);
  assert.equal(second.status, 201);
  assert.equal(second.body.id, first.body.id);

  const count = await prisma.user.count({ where: { cognitoSub: "rider-sub-2" } });
  assert.equal(count, 1);
});

test("POST /api/riders/me rejects an invalid body", async () => {
  const token = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "", lastName: "R", email: "not-an-email" });
  assert.equal(res.status, 400);
});

test("GET /api/riders/me 404s before a profile has been created", async () => {
  const token = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("PATCH /api/riders/:id/status lets an Admin suspend a rider", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-5", role: "RIDER", firstName: "Zed", lastName: "Q", email: "zed@example.com" },
  });

  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/riders/${rider.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });

  assert.equal(res.status, 200);
  assert.equal(res.body.suspended, true);
});
