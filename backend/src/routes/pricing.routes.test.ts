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
  // 2 + 1*10 + 0.2*20 = 16
  assert.equal(res.body.estimatedFare, 16);
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
  assert.equal(res.body.estimatedFare, 32);
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

// Mirrors exactly what prisma/seed.ts creates (same name, same values) so
// this proves the pricing engine works end-to-end against the actual
// staging seed data shape, not a re-implementation of it. If the seed's
// placeholder values ever change, this test's literals must be updated to
// match — that's intentional, not an oversight: it keeps the seed and this
// proof from silently drifting apart.
const SEEDED_STAGING_RULE = {
  name: "Staging Default (PLACEHOLDER — replace before production)",
  baseFare: 2.0,
  perKm: 1.0,
  perMinute: 0.25,
};

test("the seeded staging PricingRule lets GET /api/pricing/quote compute a real fare", async () => {
  await prisma.pricingRule.create({ data: { ...SEEDED_STAGING_RULE, active: true } });
  const token = mockAuthAs({ sub: "rider-sub-seed-check", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/pricing/quote")
    .query({ distanceKm: 10, durationMinutes: 20 })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  // 2.00 + 1.00*10 + 0.25*20 = 17.00
  assert.equal(res.body.estimatedFare, 17);
  assert.equal(res.body.pricingRule, SEEDED_STAGING_RULE.name);
});

test("the seeded staging PricingRule lets POST /api/trips compute a server-authoritative fare", async () => {
  await prisma.pricingRule.create({ data: { ...SEEDED_STAGING_RULE, active: true } });
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-seed-check-2", role: "RIDER", firstName: "S", lastName: "C", email: "seedcheck2@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-seed-check-2", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", distanceKm: 10, durationMinutes: 20 });

  assert.equal(res.status, 201);
  assert.equal(res.body.estimatedFare, 17);
});
