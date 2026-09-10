import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { signWebhookPayloadForTesting } from "../billing/paystack";
import { mockAuthAs, mockPaystackInitialize, mockPaystackVerify, restoreAuth, resetDb } from "../test/helpers";
import { resetRealtimeState } from "../realtime/hub";
import { calculatePayoutForPeriod } from "../services/payouts";

beforeEach(async () => {
  resetRealtimeState();
  await resetDb();
  // Not covered by resetDb() (see trips.routes.test.ts's identical pattern)
  // — the last test in this file creates a PricingRule named "Standard".
  await prisma.pricingRule.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.pricingRule.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

async function createRiderAndDriver() {
  const rider = await prisma.user.create({
    data: { cognitoSub: "ci-rider", role: "RIDER", firstName: "A", lastName: "B", email: "ci-rider@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "ci-driver", role: "DRIVER", firstName: "C", lastName: "D", email: "ci-driver@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  return { rider, driver };
}

async function createSenderAndCourier() {
  const sender = await prisma.user.create({
    data: { cognitoSub: "ci-sender", role: "RIDER", firstName: "S", lastName: "E", email: "ci-sender@example.com" },
  });
  const courierUser = await prisma.user.create({
    data: { cognitoSub: "ci-courier", role: "DRIVER", firstName: "C", lastName: "O", email: "ci-courier@example.com" },
  });
  const courier = await prisma.driver.create({ data: { userId: courierUser.id, status: "ACTIVE" } });
  return { sender, courier };
}

// ---------------------------------------------------------------------------
// Acceptance test (spec #38): ride, cash — ₦5,000 @ 20% -> RavelGo ₦1,000 /
// driver ₦4,000, recorded on both the trip and the ledger.
// ---------------------------------------------------------------------------

test("CASH ride charge locks in commission on the trip and the ledger, driver earnings visible immediately", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });

  const token = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CASH" });
  assert.equal(res.status, 201);

  const updated = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(updated.commissionRate, 0.2);
  assert.equal(updated.platformCommission, 1000);
  assert.equal(updated.driverEarnings, 4000);

  const ledgerRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "RIDE_FARE" } });
  assert.equal(ledgerRow.paymentMethod, "CASH");
  assert.equal(ledgerRow.commissionAmount, 1000);
  assert.equal(ledgerRow.driverEarnings, 4000);
});

test("WALLET ride charge locks in commission the same way as CASH", async () => {
  const { rider, driver } = await createRiderAndDriver();
  await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 1_000_000 } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });

  const token = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "WALLET" });
  assert.equal(res.status, 201);

  const updated = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(updated.platformCommission, 1000);
  assert.equal(updated.driverEarnings, 4000);
});

test("CARD ride charge only locks in commission once the Paystack webhook confirms it, never at charge time", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });

  mockPaystackInitialize();
  const token = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  const charge = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });
  assert.equal(charge.status, 201);
  const reference: string = charge.body.providerReference;

  // Not yet settled — no ledger row, no commission on the trip.
  assert.equal(await prisma.financialTransaction.count({ where: { tripId: trip.id } }), 0);
  const pending = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(pending.platformCommission, null);

  mockPaystackVerify({ status: "success" });
  const payload = { event: "charge.success", data: { reference, status: "success" } };
  const body = JSON.stringify(payload);
  const signature = signWebhookPayloadForTesting(Buffer.from(body, "utf8"));
  const webhook = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(body);
  assert.equal(webhook.status, 200);

  const settled = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(settled.platformCommission, 1000);
  assert.equal(settled.driverEarnings, 4000);
  assert.equal(await prisma.financialTransaction.count({ where: { tripId: trip.id, type: "RIDE_FARE" } }), 1);
});

// ---------------------------------------------------------------------------
// Refund
// ---------------------------------------------------------------------------

test("POST /api/trips/:id/refund (full) reverses the commission and zeroes the trip's earnings fields", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });
  const driverToken = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  await request(app).post(`/api/trips/${trip.id}/charge`).set("Authorization", `Bearer ${driverToken}`).send({ method: "CASH" });
  restoreAuth();

  const adminToken = mockAuthAs({ sub: "ci-admin", groups: ["Admin"] });
  const refund = await request(app)
    .post(`/api/trips/${trip.id}/refund`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ reason: "service issue" });
  assert.equal(refund.status, 200);
  assert.equal(refund.body.refunded, 5000);

  const refundRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "REFUND" } });
  assert.equal(refundRow.commissionAmount, -1000);
  assert.equal(refundRow.driverEarnings, -4000);

  const trippedAgain = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(trippedAgain.platformCommission, 0);
  assert.equal(trippedAgain.driverEarnings, 0);

  const payment = await prisma.payment.findUniqueOrThrow({ where: { tripId: trip.id } });
  assert.equal(payment.status, "REFUNDED");
});

test("POST /api/trips/:id/refund rejects a non-Admin caller", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });
  const token = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/trips/${trip.id}/refund`)
    .set("Authorization", `Bearer ${token}`)
    .send({ reason: "n/a" });
  assert.equal(res.status, 403);
});

// ---------------------------------------------------------------------------
// Delivery — ₦10,000 @ 20% -> RavelGo ₦2,000 / driver ₦8,000
// ---------------------------------------------------------------------------

test("CASH delivery charge locks in commission on the request and the ledger", async () => {
  const { sender, courier } = await createSenderAndCourier();
  const request_ = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: courier.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "box",
      recipientName: "R",
      recipientPhone: "123",
      estimatedFare: 10000,
      finalFare: 10000,
      status: "DELIVERED",
    },
  });

  const token = mockAuthAs({ sub: "ci-courier", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/courier-requests/${request_.id}/charge`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CASH" });
  assert.equal(res.status, 201);

  const updated = await prisma.courierRequest.findUniqueOrThrow({ where: { id: request_.id } });
  assert.equal(updated.commissionRate, 0.2);
  assert.equal(updated.platformCommission, 2000);
  assert.equal(updated.driverEarnings, 8000);
});

// ---------------------------------------------------------------------------
// Cash exclusion from the driver's bank payout — the fix for the
// commission-double-count gap the pre-implementation survey found.
// ---------------------------------------------------------------------------

test("a driver's CASH earnings never appear in their bank payout, only CARD/WALLET do", async () => {
  const cashRider = await prisma.user.create({
    data: { cognitoSub: "payout-cash-rider", role: "RIDER", firstName: "R", lastName: "1", email: "prc1@example.com" },
  });
  const cardRider = await prisma.user.create({
    data: { cognitoSub: "payout-card-rider", role: "RIDER", firstName: "R", lastName: "2", email: "prc2@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "payout-driver", role: "DRIVER", firstName: "D", lastName: "3", email: "prd3@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });

  const cashTrip = await prisma.trip.create({
    data: { riderId: cashRider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 5000, finalFare: 5000, status: "COMPLETED" },
  });
  const cardTrip = await prisma.trip.create({
    data: { riderId: cardRider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 3000, finalFare: 3000, status: "COMPLETED" },
  });

  const driverToken = mockAuthAs({ sub: "payout-driver", groups: ["Driver"] });
  const cashCharge = await request(app)
    .post(`/api/trips/${cashTrip.id}/charge`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ method: "CASH" });
  assert.equal(cashCharge.status, 201);

  mockPaystackInitialize();
  const cardCharge = await request(app)
    .post(`/api/trips/${cardTrip.id}/charge`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ method: "CARD" });
  assert.equal(cardCharge.status, 201);
  const reference: string = cardCharge.body.providerReference;

  // Confirm the CARD payment via webhook so it's SETTLED and thus payable.
  restoreAuth();
  mockPaystackVerify({ status: "success" });
  const payload = { event: "charge.success", data: { reference, status: "success" } };
  const body = JSON.stringify(payload);
  const signature = signWebhookPayloadForTesting(Buffer.from(body, "utf8"));
  await request(app).post("/api/billing/webhook").set("Content-Type", "application/json").set("x-paystack-signature", signature).send(body);

  // Backdate the ledger rows into the payout period the same way the real
  // settlement flow's timestamp would land inside a real "this month" window
  // — createdAt defaults to now, which is already inside the current period,
  // so no adjustment is needed here; find the current period directly.
  const period = new Date().toISOString().slice(0, 7);
  const calc = await calculatePayoutForPeriod(driverUser.id, period);

  // Only the ₦3,000 CARD trip's driver share (80% = 2400) is payable —
  // the ₦5,000 CASH trip's 80% (4000) never appears here, since the driver
  // already physically holds that cash.
  assert.equal(calc.grossAmount, 3000);
  assert.equal(calc.netAmount, 2400);
  assert.equal(calc.tripsIncluded, 1);
});

// ---------------------------------------------------------------------------
// Waiting charge and cancellation fee
// ---------------------------------------------------------------------------

test("POST /api/trips/:id/arrived, then starting the trip after the free waiting period, bills a real waiting charge", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 2000, status: "MATCHED" },
  });

  const driverToken = mockAuthAs({ sub: "ci-driver", groups: ["Driver"] });
  const arrived = await request(app).post(`/api/trips/${trip.id}/arrived`).set("Authorization", `Bearer ${driverToken}`);
  assert.equal(arrived.status, 200);

  // Backdate arrivedAt well past the 120s free window so the charge is real
  // and deterministic. Deliberately NOT a round multiple of 60s past the
  // free-period boundary (280s, not 300s) — the charge rounds UP to the next
  // whole chargeable minute, so a boundary that lands exactly on a minute
  // mark is one stray millisecond of test-execution time away from tipping
  // into the next minute and flaking; 280s leaves 20s of headroom.
  await prisma.trip.update({ where: { id: trip.id }, data: { arrivedAt: new Date(Date.now() - 280_000) } }); // 4 min 40s ago

  const start = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(start.status, 200);

  const updated = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  // 280s wait - 120s free = 160s chargeable, rounded up to 3 min * ₦50/min = ₦150, capped at ₦250.
  assert.equal(updated.waitingCharge, 150);

  const complete = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "COMPLETED", finalFare: 2000 });
  assert.equal(complete.status, 200);

  const charge = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ method: "CASH" });
  assert.equal(charge.status, 201);
  // ₦2,000 fare + ₦150 waiting = ₦2,150 total charged.
  assert.equal(charge.body.amount, 2150);
  // Commission is on the fare only (₦2,000 @ 20% = ₦400), not the waiting charge.
  const finalTrip = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(finalTrip.platformCommission, 400);
});

test("Cancelling a MATCHED trip past the grace period assesses a cancellation fee, driver-compensation only", async () => {
  const { rider, driver } = await createRiderAndDriver();
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 2000,
      status: "MATCHED",
      requestedAt: new Date(Date.now() - 5 * 60_000), // 5 min ago, past the 2 min grace period
    },
  });

  const riderToken = mockAuthAs({ sub: "ci-rider", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${riderToken}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.cancellationFee, 1500);

  const ledgerRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "CANCELLATION_FEE" } });
  assert.equal(ledgerRow.commissionAmount, 0);
  assert.equal(ledgerRow.driverEarnings, 1500);
});

test("Cancelling a REQUESTED trip (no driver dispatched yet) never assesses a fee", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "ci-rider-2", role: "RIDER", firstName: "R", lastName: "2", email: "cir2@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 2000, status: "REQUESTED" },
  });

  const token = mockAuthAs({ sub: "ci-rider-2", groups: ["Rider"] });
  const res = await request(app).post(`/api/trips/${trip.id}/cancel`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.cancellationFee, null);
});

// ---------------------------------------------------------------------------
// Security: the client can never assert its own commission/earnings figures.
// ---------------------------------------------------------------------------

test("POST /api/trips ignores a client-supplied platformCommission/driverEarnings entirely", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 2, perKm: 1, perMinute: 0.2 } });
  const rider = await prisma.user.create({
    data: { cognitoSub: "ci-cheat-rider", role: "RIDER", firstName: "R", lastName: "C", email: "circ@example.com" },
  });
  const token = mockAuthAs({ sub: "ci-cheat-rider", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({
      pickup: "A",
      destination: "B",
      pickupLat: 6.5244,
      pickupLng: 3.3792,
      dropoffLat: 6.4478,
      dropoffLng: 3.4723,
      // The attack: try to assert RavelGo takes 0% commission and the driver
      // gets everything.
      platformCommission: 0,
      driverEarnings: 999999,
      commissionRate: 0,
    });
  assert.equal(res.status, 201);
  assert.equal(res.body.platformCommission, null); // not settled yet — never the injected value
  assert.equal(res.body.driverEarnings, null);
});
