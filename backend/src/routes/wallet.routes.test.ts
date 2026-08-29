import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { mockAuthAs, mockPaymentIntentCreate, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function createRider(cognitoSub: string) {
  return prisma.user.create({
    data: { cognitoSub, role: "RIDER", firstName: "A", lastName: "B", email: `${cognitoSub}@example.com` },
  });
}

// Build a signed wallet-topup webhook the same way Stripe would.
function signedTopupEvent(intentId: string, type: "payment_intent.succeeded" | "payment_intent.payment_failed") {
  const payload = JSON.stringify({
    id: "evt_wallet_1",
    object: "event",
    type,
    data: { object: { id: intentId, object: "payment_intent", metadata: { type: "wallet_topup" } } },
  });
  const signature = stripeClient.webhooks.generateTestHeaderString({ payload, secret: env.STRIPE_WEBHOOK_SECRET! });
  return { payload, signature };
}

test("GET /wallet/me starts every user at a zero balance", async () => {
  await createRider("rider-w1");
  const token = mockAuthAs({ sub: "rider-w1", groups: ["Rider"] });
  const res = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.balance, 0);
});

test("wallet top-up credits the balance only after Stripe confirms via the signed webhook", async () => {
  await createRider("rider-w2");
  const intentId = mockPaymentIntentCreate("pi_topup_1");
  const token = mockAuthAs({ sub: "rider-w2", groups: ["Rider"] });

  // 1. Request a top-up: creates a PENDING transaction, balance still 0.
  const topup = await request(app)
    .post("/api/wallet/topup")
    .set("Authorization", `Bearer ${token}`)
    .send({ amount: 30 });
  assert.equal(topup.status, 201);
  assert.equal(topup.body.status, "PENDING");
  assert.ok(topup.body.clientSecret);

  const beforeWebhook = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(beforeWebhook.body.balance, 0); // not credited yet

  // 2. Stripe confirms the charge -> webhook credits the balance.
  const { payload, signature } = signedTopupEvent(intentId, "payment_intent.succeeded");
  const hook = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(payload);
  assert.equal(hook.status, 200);

  const afterWebhook = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(afterWebhook.body.balance, 30);

  // 3. A duplicate webhook delivery must not double-credit.
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(payload);
  const afterDuplicate = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(afterDuplicate.body.balance, 30);
});

test("a failed top-up webhook leaves the balance at zero and marks the transaction FAILED", async () => {
  const rider = await createRider("rider-w3");
  const intentId = mockPaymentIntentCreate("pi_topup_fail");
  const token = mockAuthAs({ sub: "rider-w3", groups: ["Rider"] });

  await request(app).post("/api/wallet/topup").set("Authorization", `Bearer ${token}`).send({ amount: 15 });

  const { payload, signature } = signedTopupEvent(intentId, "payment_intent.payment_failed");
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(payload);

  const wallet = await prisma.walletAccount.findUnique({ where: { userId: rider.id } });
  assert.equal(wallet?.balanceCents, 0);
  const txn = await prisma.walletTransaction.findUnique({ where: { providerReference: intentId } });
  assert.equal(txn?.status, "FAILED");
});

test("wallet top-up rejects a malformed amount", async () => {
  await createRider("rider-w4");
  const token = mockAuthAs({ sub: "rider-w4", groups: ["Rider"] });
  for (const amount of [-5, 0, 1e9]) {
    const res = await request(app).post("/api/wallet/topup").set("Authorization", `Bearer ${token}`).send({ amount });
    assert.equal(res.status, 400, `expected 400 for amount ${amount}`);
  }
});
