import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

// These prove P0 #4: an ordinary Prisma error raised inside a bare `async`
// route handler (no try/catch) is converted to a controlled HTTP response by
// errorHandler instead of becoming an unhandledRejection. If the fix were
// absent the rejection would escape the handler; supertest would see a hung
// socket / aborted request rather than a JSON 409, and — in a real deploy —
// the process would exit. A clean 409 body is the proof.

// resetDb() doesn't clear the promotion tables, so isolate them here — these
// tests assert exact promotion/redemption row counts and must not see rows
// left by another suite.
beforeEach(async () => {
  await resetDb();
  await prisma.promotionRedemption.deleteMany();
  await prisma.promotion.deleteMany();
});
afterEach(() => restoreAuth());
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("duplicate unique key in a bare async handler returns 409, not a crash", async () => {
  const token = mockAuthAs({ sub: "admin-ae", groups: ["Admin"] });
  const body = { code: "SUMMER10", description: "Summer promo", discountPercent: 10 };

  const first = await request(app)
    .post("/api/promotions")
    .set("Authorization", `Bearer ${token}`)
    .send(body);
  assert.equal(first.status, 201);

  // Same code again → Promotion.code @unique → P2002, thrown with no try/catch.
  const second = await request(app)
    .post("/api/promotions")
    .set("Authorization", `Bearer ${token}`)
    .send(body);
  assert.equal(second.status, 409);
  assert.equal(second.body.error.code, "CONFLICT");
  // The raw Prisma message / constraint name must not leak to the client.
  assert.ok(!JSON.stringify(second.body).toLowerCase().includes("prisma"));
});

test("the process is still alive and serving after a thrown duplicate-key error", async () => {
  const token = mockAuthAs({ sub: "admin-ae", groups: ["Admin"] });
  const body = { code: "WINTER5", description: "Winter promo", discountPercent: 5 };
  await request(app).post("/api/promotions").set("Authorization", `Bearer ${token}`).send(body);
  await request(app).post("/api/promotions").set("Authorization", `Bearer ${token}`).send(body); // throws P2002

  // A subsequent unrelated request must still succeed — the server did not die.
  const health = await request(app).get("/health");
  assert.equal(health.status, 200);
});

test("concurrent redemptions of the same promotion settle to one success + one conflict", async () => {
  const admin = mockAuthAs({ sub: "admin-ae", groups: ["Admin"] });
  await request(app)
    .post("/api/promotions")
    .set("Authorization", `Bearer ${admin}`)
    .send({ code: "RACE1", description: "Race promo", discountPercent: 15 });

  await prisma.user.create({
    data: { cognitoSub: "rider-race", role: "RIDER", firstName: "R", lastName: "R", email: "race@example.com" },
  });
  restoreAuth();
  const rider = mockAuthAs({ sub: "rider-race", groups: ["Rider"] });

  // Fire both at once: they both pass the pre-check, one wins the unique index,
  // the loser throws P2002 inside the $transaction. Neither may crash the app.
  const [a, b] = await Promise.all([
    request(app).post("/api/promotions/RACE1/redeem").set("Authorization", `Bearer ${rider}`),
    request(app).post("/api/promotions/RACE1/redeem").set("Authorization", `Bearer ${rider}`),
  ]);
  const statuses = [a.status, b.status].sort();
  assert.deepEqual(statuses, [201, 409]);

  // Exactly one redemption row exists — no double effect.
  const count = await prisma.promotionRedemption.count();
  assert.equal(count, 1);
});
