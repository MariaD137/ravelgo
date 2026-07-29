import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.promotionRedemption.deleteMany();
  await prisma.promotion.deleteMany();
  await prisma.loyaltyTier.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.promotionRedemption.deleteMany();
  await prisma.promotion.deleteMany();
  await prisma.loyaltyTier.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

test("POST /api/loyalty-tiers rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/loyalty-tiers")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Gold", minCompletedTrips: 50, discountPercent: 10 });
  assert.equal(res.status, 403);
});

test("POST /api/loyalty-tiers lets an Admin create a tier, then it's listed", async () => {
  const adminToken = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const create = await request(app)
    .post("/api/loyalty-tiers")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ name: "Silver", minCompletedTrips: 10, discountPercent: 5 });
  assert.equal(create.status, 201);

  restoreAuth();
  const riderToken = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const list = await request(app).get("/api/loyalty-tiers").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 1);
  assert.equal(list.body[0].name, "Silver");
});

test("GET /api/riders/me/loyalty computes the caller's current tier from completed trips", async () => {
  await prisma.loyaltyTier.create({ data: { name: "Bronze", minCompletedTrips: 0, discountPercent: 0 } });
  await prisma.loyaltyTier.create({ data: { name: "Silver", minCompletedTrips: 2, discountPercent: 5 } });
  await prisma.loyaltyTier.create({ data: { name: "Gold", minCompletedTrips: 10, discountPercent: 10 } });

  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-3", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  for (let i = 0; i < 3; i++) {
    await prisma.trip.create({
      data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 10, status: "COMPLETED" },
    });
  }

  const token = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me/loyalty").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.completedTrips, 3);
  assert.equal(res.body.currentTier.name, "Silver");
});

test("POST /api/promotions/:code/redeem applies once, then rejects a second redemption", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const adminToken = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  await request(app)
    .post("/api/promotions")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ code: "WELCOME10", description: "10% off", discountPercent: 10 });

  restoreAuth();
  const token = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const first = await request(app).post("/api/promotions/WELCOME10/redeem").set("Authorization", `Bearer ${token}`);
  assert.equal(first.status, 201);
  assert.equal(first.body.discountPercent, 10);

  const second = await request(app).post("/api/promotions/WELCOME10/redeem").set("Authorization", `Bearer ${token}`);
  assert.equal(second.status, 409);
});

test("POST /api/promotions/:code/redeem 404s for an unknown code", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-5", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const res = await request(app).post("/api/promotions/DOES-NOT-EXIST/redeem").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});
