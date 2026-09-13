import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { signWebhookPayloadForTesting } from "../billing/paystack";
import { mockAuthAs, mockPaystackVerify, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// Send the signed body as a string, not `Buffer.from(body)` — superagent's
// JSON serializer runs on whatever `.send()` is given when Content-Type is
// "application/json", and `JSON.stringify(someBuffer)` produces
// `{"type":"Buffer","data":[...]}` instead of the actual bytes, which
// silently breaks every signature check below (discovered by that exact
// failure while writing these tests).
function signedWebhookRequest(payload: unknown) {
  const body = JSON.stringify(payload);
  const signature = signWebhookPayloadForTesting(Buffer.from(body, "utf8"));
  return { body, signature };
}

async function createChargedTrip(providerReference: string) {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-1", role: "DRIVER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 10, finalFare: 10, status: "COMPLETED" },
  });
  const payment = await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 10, status: "PENDING", provider: "PAYSTACK", providerReference },
  });
  return payment;
}

test("POST /api/billing/webhook rejects a request with no x-paystack-signature header", async () => {
  const res = await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").send("{}");
  assert.equal(res.status, 400);
});

test("POST /api/billing/webhook rejects an invalid signature", async () => {
  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", "not-a-real-signature")
    .send("{}");
  assert.equal(res.status, 400);
});

test("charge.success marks the matching Payment SUCCEEDED (verified via the trusted verify endpoint, not the webhook body alone)", async () => {
  const payment = await createChargedTrip("ravelgo_trip_success_1");
  mockPaystackVerify({ status: "success" });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_trip_success_1", status: "success" },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
  const updated = await prisma.payment.findUnique({ where: { id: payment.id } });
  assert.equal(updated?.status, "SUCCEEDED");
  assert.ok(updated?.paidAt);

  const notifications = await prisma.notification.findMany({ where: { userId: payment.userId } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "PAYMENT_SUCCEEDED");
  assert.equal(notifications[0].referenceId, payment.tripId);
});

test("charge.failed (verification reports failed) marks the matching Payment FAILED", async () => {
  const payment = await createChargedTrip("ravelgo_trip_fail_1");
  mockPaystackVerify({ status: "failed" });
  const { body, signature } = signedWebhookRequest({
    event: "charge.failed",
    data: { reference: "ravelgo_trip_fail_1", status: "failed" },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
  const updated = await prisma.payment.findUnique({ where: { id: payment.id } });
  assert.equal(updated?.status, "FAILED");
  assert.equal(updated?.paidAt, null);

  const notifications = await prisma.notification.findMany({ where: { userId: payment.userId } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "PAYMENT_FAILED");
});

test("a redelivered webhook for an already-settled Payment is a no-op (idempotency)", async () => {
  const payment = await createChargedTrip("ravelgo_trip_dup_1");
  mockPaystackVerify({ status: "success" });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_trip_dup_1", status: "success" },
  });

  await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").set("x-paystack-signature", signature).send(body);
  const res = await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").set("x-paystack-signature", signature).send(body);

  assert.equal(res.status, 200);
  const notifications = await prisma.notification.findMany({ where: { userId: payment.userId } });
  // Exactly one PAYMENT_SUCCEEDED, not two — the second delivery found the
  // Payment already SUCCEEDED (not PENDING) and didn't re-apply it.
  assert.equal(notifications.length, 1);
});

test("an event for an unknown reference is accepted but updates nothing", async () => {
  mockPaystackVerify({ status: "success" });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_trip_does_not_exist", status: "success" },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
});

// --- Finding 4 (security audit): wallet top-up webhook race ----------------
// creditWalletFromTopup previously read a WalletTransaction's status, checked
// it was PENDING, then issued a plain (unconditional) update — a TOCTOU race:
// two concurrent/redelivered webhooks for the same reference could both read
// "PENDING" before either committed, and both would go on to credit the
// wallet. It's fixed to claim the PENDING -> COMPLETED transition with a
// conditional updateMany (same pattern the other three branches of this
// webhook already use), so only one caller's claim can ever succeed.

async function seedPendingTopup(providerReference: string, amountCents: number) {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-topup-1", role: "RIDER", firstName: "A", lastName: "B", email: "topup@example.com" },
  });
  const wallet = await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 0 } });
  await prisma.walletTransaction.create({
    data: { walletId: wallet.id, type: "TOPUP", status: "PENDING", amountCents, providerReference },
  });
  return wallet;
}

test("wallet_topup charge.success credits the wallet balance", async () => {
  const wallet = await seedPendingTopup("ravelgo_topup_1", 5000);
  mockPaystackVerify({ status: "success", metadata: { type: "wallet_topup" } });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_topup_1", status: "success" },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
  const updated = await prisma.walletAccount.findUnique({ where: { id: wallet.id } });
  assert.equal(updated?.balanceCents, 5000);
  const txn = await prisma.walletTransaction.findUnique({ where: { providerReference: "ravelgo_topup_1" } });
  assert.equal(txn?.status, "COMPLETED");
});

test("a redelivered wallet_topup webhook does not double-credit the balance", async () => {
  const wallet = await seedPendingTopup("ravelgo_topup_2", 5000);
  mockPaystackVerify({ status: "success", metadata: { type: "wallet_topup" } });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_topup_2", status: "success" },
  });

  await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").set("x-paystack-signature", signature).send(body);
  const second = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);

  assert.equal(second.status, 200);
  const updated = await prisma.walletAccount.findUnique({ where: { id: wallet.id } });
  assert.equal(updated?.balanceCents, 5000); // credited once, not 10000
});

test("two concurrent (redelivered) wallet_topup webhooks for the same reference credit the balance exactly once", async () => {
  const wallet = await seedPendingTopup("ravelgo_topup_3", 7500);
  mockPaystackVerify({ status: "success", metadata: { type: "wallet_topup" } });
  const { body, signature } = signedWebhookRequest({
    event: "charge.success",
    data: { reference: "ravelgo_topup_3", status: "success" },
  });
  const fire = () =>
    request(app).post("/api/billing/webhook").set("Content-Type", "application/json").set("x-paystack-signature", signature).send(body);

  const [a, b] = await Promise.all([fire(), fire()]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);

  // The race this closes: both requests reading PENDING before either
  // committed would previously both credit the wallet, landing on 15000.
  const updated = await prisma.walletAccount.findUnique({ where: { id: wallet.id } });
  assert.equal(updated?.balanceCents, 7500);
});

test("mockAuthAs/restoreAuth still work normally for other routes after webhook tests run", async () => {
  const token = mockAuthAs({ sub: "rider-sub-9", groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404); // profile doesn't exist, but auth itself worked
});
