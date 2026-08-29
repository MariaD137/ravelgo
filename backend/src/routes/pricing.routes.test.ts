import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

test("POST /api/pricing-rules rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/pricing-rules")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 });
  assert.equal(res.status, 403);
});

test("POST /api/pricing-rules lets an Admin create a rule, then it's listed", async () => {
  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const create = await request(app)
    .post("/api/pricing-rules")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 });
  assert.equal(create.status, 201);

  const list = await request(app).get("/api/pricing-rules").set("Authorization", `Bearer ${token}`);
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 1);
});

test("PATCH /api/pricing-rules/:id lets an Admin deactivate a rule", async () => {
  const rule = await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/pricing-rules/${rule.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ active: false });
  assert.equal(res.status, 200);
  assert.equal(res.body.active, false);
});

test("POST /api/surge-zones lets an Admin create a zone, then it's listed", async () => {
  const token = mockAuthAs({ sub: "admin-sub-3", groups: ["Admin"] });
  const create = await request(app)
    .post("/api/surge-zones")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Downtown", location: "City center", multiplier: 1.5 });
  assert.equal(create.status, 201);

  const list = await request(app).get("/api/surge-zones").set("Authorization", `Bearer ${token}`);
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 1);
});

test("GET /api/pricing/quote computes a fare from the active rule, with no surge by default", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/pricing/quote")
    .query({ distanceKm: 10, durationMinutes: 20 })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  // subtotal 2 + 1*10 + 0.2*20 = 16; + 7.5% VAT (1.2) = 17.2 tax-inclusive
  assert.equal(res.body.subtotal, 16);
  assert.equal(res.body.tax, 1.2);
  assert.equal(res.body.estimatedFare, 17.2);
  assert.equal(res.body.surgeMultiplier, 1);
});

test("GET /api/pricing/quote applies an active surge zone's multiplier when it matches", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  await prisma.surgeZone.create({ data: { name: "Downtown", location: "City center", multiplier: 2 } });
  const token = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/pricing/quote")
    .query({ distanceKm: 10, durationMinutes: 20, zone: "downtown" })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  // subtotal 16*2 = 32; + 7.5% VAT (2.4) = 34.4 tax-inclusive
  assert.equal(res.body.subtotal, 32);
  assert.equal(res.body.tax, 2.4);
  assert.equal(res.body.estimatedFare, 34.4);
  assert.equal(res.body.surgeMultiplier, 2);
  assert.equal(res.body.surgeZone, "Downtown");
});

test("GET /api/pricing/quote 409s when no pricing rule is active", async () => {
  const token = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/pricing/quote")
    .query({ distanceKm: 5, durationMinutes: 10 })
    .set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 409);
});
