import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { signWebhookPayloadForTesting } from "../billing/paystack";
import { mockAuthAs, mockPaystackInitialize, mockPaystackVerify, restoreAuth, resetDb } from "../test/helpers";

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

// Build a signed wallet-topup webhook the same way Paystack would, and stub
// the verify-endpoint call the handler makes before trusting it. The topup
// route's HTTP response never carries the raw reference (only the
// authorizationUrl), so tests read it back off the WalletTransaction row
// the route just created.
function signedTopupEvent(reference: string, succeeded: boolean) {
  mockPaystackVerify({ status: succeeded ? "success" : "failed", metadata: { type: "wallet_topup" } });
  const payload = JSON.stringify({
    event: succeeded ? "charge.success" : "charge.failed",
    data: { reference, status: succeeded ? "success" : "failed" },
  });
  const signature = signWebhookPayloadForTesting(Buffer.from(payload, "utf8"));
  return { payload, signature };
}

async function latestPendingTopupReference(): Promise<string> {
  const txn = await prisma.walletTransaction.findFirstOrThrow({
    where: { type: "TOPUP", status: "PENDING" },
    orderBy: { createdAt: "desc" },
  });
  return txn.providerReference!;
}

test("GET /wallet/me starts every user at a zero balance", async () => {
  await createRider("rider-w1");
  const token = mockAuthAs({ sub: "rider-w1", groups: ["Rider"] });
  const res = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.balance, 0);
});

test("wallet top-up credits the balance only after Paystack confirms via the signed webhook", async () => {
  await createRider("rider-w2");
  mockPaystackInitialize();
  const token = mockAuthAs({ sub: "rider-w2", groups: ["Rider"] });

  // 1. Request a top-up: creates a PENDING transaction, balance still 0.
  const topup = await request(app)
    .post("/api/wallet/topup")
    .set("Authorization", `Bearer ${token}`)
    .send({ amount: 30 });
  assert.equal(topup.status, 201);
  assert.equal(topup.body.status, "PENDING");
  assert.ok(topup.body.authorizationUrl);

  const beforeWebhook = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(beforeWebhook.body.balance, 0); // not credited yet

  // 2. Paystack confirms the charge -> webhook credits the balance.
  const reference = await latestPendingTopupReference();
  const { payload, signature } = signedTopupEvent(reference, true);
  const hook = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(payload);
  assert.equal(hook.status, 200);

  const afterWebhook = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(afterWebhook.body.balance, 30);

  // 3. A duplicate webhook delivery must not double-credit.
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(payload);
  const afterDuplicate = await request(app).get("/api/wallet/me").set("Authorization", `Bearer ${token}`);
  assert.equal(afterDuplicate.body.balance, 30);
});

test("a failed top-up webhook leaves the balance at zero and marks the transaction FAILED", async () => {
  const rider = await createRider("rider-w3");
  mockPaystackInitialize();
  const token = mockAuthAs({ sub: "rider-w3", groups: ["Rider"] });

  await request(app).post("/api/wallet/topup").set("Authorization", `Bearer ${token}`).send({ amount: 15 });
  const reference = await latestPendingTopupReference();

  const { payload, signature } = signedTopupEvent(reference, false);
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(payload);

  const wallet = await prisma.walletAccount.findUnique({ where: { userId: rider.id } });
  assert.equal(wallet?.balanceCents, 0);
  const txn = await prisma.walletTransaction.findUnique({ where: { providerReference: reference } });
  assert.equal(txn?.status, "FAILED");
});

test("an authorized third party can fund another user's wallet; only the beneficiary is credited", async () => {
  const payer = await createRider("payer-1");
  const beneficiary = await createRider("beneficiary-1");
  mockPaystackInitialize();
  const payerToken = mockAuthAs({ sub: "payer-1", groups: ["Rider"] });

  // Payer tops up the beneficiary's wallet by email.
  const topup = await request(app)
    .post("/api/wallet/topup")
    .set("Authorization", `Bearer ${payerToken}`)
    .send({ amount: 50, beneficiaryEmail: "beneficiary-1@example.com" });
  assert.equal(topup.status, 201);
  assert.equal(topup.body.beneficiary, "beneficiary-1@example.com");
  const reference = await latestPendingTopupReference();

  // Paystack confirms the charge.
  const { payload, signature } = signedTopupEvent(reference, true);
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(payload);

  // The beneficiary's balance rose; the payer's did not.
  const beneficiaryWallet = await prisma.walletAccount.findUnique({ where: { userId: beneficiary.id } });
  assert.equal(beneficiaryWallet?.balanceCents, 5000);
  const payerWallet = await prisma.walletAccount.findUnique({ where: { userId: payer.id } });
  assert.equal(payerWallet?.balanceCents ?? 0, 0);

  // The ledger permanently records who funded it.
  const txn = await prisma.walletTransaction.findUnique({ where: { providerReference: reference } });
  assert.equal(txn?.walletId, beneficiaryWallet?.id);
  assert.equal(txn?.fundedBySub, "payer-1");
});

test("funding a non-existent beneficiary is rejected with 404", async () => {
  await createRider("payer-2");
  const token = mockAuthAs({ sub: "payer-2", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/wallet/topup")
    .set("Authorization", `Bearer ${token}`)
    .send({ amount: 20, beneficiaryEmail: "nobody@example.com" });
  assert.equal(res.status, 404);
});

test("wallet top-up rejects a malformed amount", async () => {
  await createRider("rider-w4");
  const token = mockAuthAs({ sub: "rider-w4", groups: ["Rider"] });
  for (const amount of [-5, 0, 1e9]) {
    const res = await request(app).post("/api/wallet/topup").set("Authorization", `Bearer ${token}`).send({ amount });
    assert.equal(res.status, 400, `expected 400 for amount ${amount}`);
  }
});
