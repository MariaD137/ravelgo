import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

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
  const signature = stripeClient.webhooks.generateTestHeaderString({
    payload: body,
    secret: env.STRIPE_WEBHOOK_SECRET!,
  });
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
    data: { tripId: trip.id, userId: rider.id, amount: 10, status: "PENDING", providerReference },
  });
  return payment;
}

test("POST /api/billing/webhook rejects a request with no stripe-signature header", async () => {
  const res = await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").send("{}");
  assert.equal(res.status, 400);
});

test("POST /api/billing/webhook rejects an invalid signature", async () => {
  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", "t=1,v1=not-a-real-signature")
    .send("{}");
  assert.equal(res.status, 400);
});

test("payment_intent.succeeded marks the matching Payment SUCCEEDED", async () => {
  const payment = await createChargedTrip("pi_test_success_1");
  const { body, signature } = signedWebhookRequest({
    id: "evt_test_1",
    object: "event",
    type: "payment_intent.succeeded",
    data: { object: { id: "pi_test_success_1", object: "payment_intent" } },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
  const updated = await prisma.payment.findUnique({ where: { id: payment.id } });
  assert.equal(updated?.status, "SUCCEEDED");
  assert.ok(updated?.paidAt);
});

test("payment_intent.payment_failed marks the matching Payment FAILED", async () => {
  const payment = await createChargedTrip("pi_test_fail_1");
  const { body, signature } = signedWebhookRequest({
    id: "evt_test_2",
    object: "event",
    type: "payment_intent.payment_failed",
    data: { object: { id: "pi_test_fail_1", object: "payment_intent" } },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
  const updated = await prisma.payment.findUnique({ where: { id: payment.id } });
  assert.equal(updated?.status, "FAILED");
  assert.equal(updated?.paidAt, null);
});

test("an event for an unknown PaymentIntent id is accepted but updates nothing", async () => {
  const { body, signature } = signedWebhookRequest({
    id: "evt_test_3",
    object: "event",
    type: "payment_intent.succeeded",
    data: { object: { id: "pi_does_not_exist", object: "payment_intent" } },
  });

  const res = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(body);

  assert.equal(res.status, 200);
});

test("mockAuthAs/restoreAuth still work normally for other routes after webhook tests run", async () => {
  const token = mockAuthAs({ sub: "rider-sub-9", groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404); // profile doesn't exist, but auth itself worked
});
