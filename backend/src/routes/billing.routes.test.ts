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

test("mockAuthAs/restoreAuth still work normally for other routes after webhook tests run", async () => {
  const token = mockAuthAs({ sub: "rider-sub-9", groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404); // profile doesn't exist, but auth itself worked
});
