import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, mockPaystackTransfer, restoreAuth, resetDb, mockCognitoAdminUserStatus } from "../test/helpers";
import { signWebhookPayloadForTesting } from "../billing/paystack";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
  return { user, driver };
}

// Regression coverage for the driverId confusion bug: DriverBankAccount and
// Payout are FKs to User.id (see prisma/schema.prisma), not the Cognito sub
// and not Driver.id. Before the fix, every route below either threw a
// foreign-key violation or silently returned nothing.

test("POST /payouts/bank-account creates a row the same driver can then read back", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const create = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send({
      accountHolderName: "Driver One",
      bankName: "First Bank",
      accountNumber: "0123456789",
      routingNumber: "021000021",
    });
  assert.equal(create.status, 201);

  const read = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);
  assert.equal(read.status, 200);
  assert.equal(read.body.accountHolderName, "Driver One");
  // Full account/routing numbers are never returned — only the last 4 digits.
  assert.equal(read.body.accountNumber, "••••6789");
  assert.equal(read.body.routingNumber, "••••0021");
  assert.ok(!JSON.stringify(read.body).includes("0123456789"));
});

test("GET /payouts/history only returns the calling driver's own payouts, including ones an Admin created", async () => {
  const { user: userA } = await createDriver("driver-sub-2");
  const { user: userB } = await createDriver("driver-sub-3");

  const adminToken = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const createRes = await request(app)
    .post("/api/payouts/create")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ driverId: userA.id, period: "2026-01", amount: 500 });
  assert.equal(createRes.status, 201);
  restoreAuth();

  // A payout for a different driver must never show up in A's history.
  await prisma.payout.create({ data: { driverId: userB.id, amount: 999, period: "2026-01", status: "PENDING" } });

  const driverAToken = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const history = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${driverAToken}`);

  assert.equal(history.status, 200);
  assert.equal(history.body.data.length, 1);
  assert.equal(history.body.data[0].amount, 500);
});

test("GET /payouts/:id 404s a payout that belongs to a different driver", async () => {
  const { user: userA } = await createDriver("driver-sub-4");
  const { user: userB } = await createDriver("driver-sub-5");

  const payout = await prisma.payout.create({
    data: { driverId: userB.id, amount: 250, period: "2026-01", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app).get(`/api/payouts/${payout.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
  void userA;
});

test("POST /payouts/calculate computes a real amount from the driver's completed, paid trips", async () => {
  const { user, driver } = await createDriver("driver-sub-6");
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "R", lastName: "I", email: "r@example.com" },
  });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 100,
      finalFare: 100,
      status: "COMPLETED",
      completedAt: new Date("2026-01-15"),
    },
  });
  const payment = await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 100, status: "SUCCEEDED", paidAt: new Date("2026-01-15") },
  });
  // calculatePayoutForPeriod sources gross/commission/driver-earnings from
  // the FinancialTransaction ledger (services/ledger.ts), written by
  // recordRideCommission() at real payment settlement — not raw Payment rows.
  await prisma.financialTransaction.create({
    data: {
      type: "RIDE_FARE",
      tripId: trip.id,
      paymentId: payment.id,
      customerId: rider.id,
      driverId: driver.id,
      grossAmount: 100,
      commissionRate: 0.2,
      commissionAmount: 20,
      driverEarnings: 80,
      paymentMethod: "CARD",
      status: "SETTLED",
      createdAt: new Date("2026-01-15"),
    },
  });

  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .post("/api/payouts/calculate")
    .set("Authorization", `Bearer ${token}`)
    .send({ driverId: user.id, period: "2026-01" });

  assert.equal(res.status, 200);
  assert.equal(res.body.tripsIncluded, 1);
  assert.equal(res.body.grossAmount, 100);
  // RavelGo's default commission is 20% (services/commission.ts); the
  // driver's net is the remaining 80%.
  assert.equal(res.body.platformFee, 20);
  assert.equal(res.body.netAmount, 80);
});

test("Admin-only payout endpoints reject a Driver caller", async () => {
  const { user } = await createDriver("driver-sub-7");
  const token = mockAuthAs({ sub: "driver-sub-7", groups: ["Driver"] });

  for (const call of [
    () => request(app).post("/api/payouts/calculate").send({ driverId: user.id, period: "2026-01" }),
    () => request(app).post("/api/payouts/create").send({ driverId: user.id, period: "2026-01" }),
    () => request(app).get("/api/payouts"),
  ]) {
    const res = await call().set("Authorization", `Bearer ${token}`);
    assert.equal(res.status, 403);
  }
});

test("a Finance Viewer admin can list payouts but cannot process one", async () => {
  const { user: driver } = await createDriver("driver-sub-8");
  await prisma.user.create({
    data: { cognitoSub: "finance-viewer-1", role: "ADMIN", firstName: "Fin", lastName: "V", email: "fv1@example.com", adminRole: "FINANCE_VIEWER" },
  });
  const token = mockAuthAs({ sub: "finance-viewer-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const list = await request(app).get("/api/payouts").set("Authorization", `Bearer ${token}`);
  assert.equal(list.status, 200);

  const create = await request(app)
    .post("/api/payouts/create")
    .set("Authorization", `Bearer ${token}`)
    .send({ driverId: driver.id, period: "2026-01" });
  assert.equal(create.status, 403);
});

test("POST /payouts/:id/process moves PENDING to PROCESSING without fabricating a transactionId", async () => {
  const { user } = await createDriver("driver-sub-process-1");
  const payout = await prisma.payout.create({
    data: { driverId: user.id, amount: 5000, period: "2026-02", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "super-payout-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).post(`/api/payouts/${payout.id}/process`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "PROCESSING");
  // Previously this endpoint stamped a fabricated `stripe_payout_<timestamp>`
  // value here — a fake reference that was never sent to, or verified by,
  // any real payment provider. It must stay unset until a real transfer
  // reference exists (see POST /payouts/:id/complete below).
  assert.equal(res.body.transactionId, null);
});

test("POST /payouts/:id/process initiates a real Paystack transfer when the driver's bank account has a bank code, and finalizes on the transfer.success webhook", async () => {
  const { user } = await createDriver("driver-sub-process-3");
  await prisma.driverBankAccount.create({
    data: { driverId: user.id, accountHolderName: "Driver Three", bankName: "GTBank", bankCode: "058", accountNumber: "0011122233" },
  });
  const payout = await prisma.payout.create({
    data: { driverId: user.id, amount: 5000, period: "2026-03", status: "PENDING" },
  });

  mockPaystackTransfer();
  const token = mockAuthAs({ sub: "super-payout-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).post(`/api/payouts/${payout.id}/process`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "PROCESSING");
  assert.equal(res.body.provider, "PAYSTACK");
  assert.equal(res.body.transactionId, `ravelgo_payout_${payout.id}`);

  // The transfer recipient is cached on the bank account for the next payout.
  const account = await prisma.driverBankAccount.findUnique({ where: { driverId: user.id } });
  assert.equal(account?.paystackRecipientCode, "RCP_test_1");

  // The transfer.success webhook (billing.routes.ts) finalizes it.
  restoreAuth();
  const payload = JSON.stringify({ event: "transfer.success", data: { reference: `ravelgo_payout_${payout.id}` } });
  const signature = signWebhookPayloadForTesting(Buffer.from(payload, "utf8"));
  const hook = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("x-paystack-signature", signature)
    .send(payload);
  assert.equal(hook.status, 200);

  const completed = await prisma.payout.findUniqueOrThrow({ where: { id: payout.id } });
  assert.equal(completed.status, "COMPLETED");
  assert.ok(completed.completedAt);

  const notifications = await prisma.notification.findMany({ where: { userId: user.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "PAYOUT_COMPLETED");
});

test("POST /payouts/:id/complete records the real transactionId the caller supplies", async () => {
  const { user } = await createDriver("driver-sub-process-2");
  const payout = await prisma.payout.create({
    data: { driverId: user.id, amount: 5000, period: "2026-02", status: "PROCESSING" },
  });

  const token = mockAuthAs({ sub: "super-payout-2", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .post(`/api/payouts/${payout.id}/complete`)
    .set("Authorization", `Bearer ${token}`)
    .send({ transactionId: "real-bank-transfer-ref-12345" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.equal(res.body.transactionId, "real-bank-transfer-ref-12345");
});

// SE-4: a payout must never reach COMPLETED without a real transaction
// reference — this used to be optional, letting an admin complete a payout
// with no proof a transfer ever happened.
test("POST /payouts/:id/complete rejects a missing or blank transactionId", async () => {
  const { user } = await createDriver("driver-sub-process-3");
  const payout = await prisma.payout.create({
    data: { driverId: user.id, amount: 5000, period: "2026-03", status: "PROCESSING" },
  });
  const token = mockAuthAs({ sub: "super-payout-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const missing = await request(app)
    .post(`/api/payouts/${payout.id}/complete`)
    .set("Authorization", `Bearer ${token}`)
    .send({});
  assert.equal(missing.status, 400);

  const blank = await request(app)
    .post(`/api/payouts/${payout.id}/complete`)
    .set("Authorization", `Bearer ${token}`)
    .send({ transactionId: "   " });
  assert.equal(blank.status, 400);

  const stillProcessing = await prisma.payout.findUnique({ where: { id: payout.id } });
  assert.equal(stillProcessing?.status, "PROCESSING");
  assert.equal(stillProcessing?.transactionId, null);
});

// SE-4: the same real transaction reference must never be attributable to
// two different payouts.
test("POST /payouts/:id/complete rejects a transactionId already used by another payout", async () => {
  const { user: userA } = await createDriver("driver-sub-process-4a");
  const { user: userB } = await createDriver("driver-sub-process-4b");
  const payoutA = await prisma.payout.create({
    data: { driverId: userA.id, amount: 5000, period: "2026-04", status: "PROCESSING" },
  });
  const payoutB = await prisma.payout.create({
    data: { driverId: userB.id, amount: 7000, period: "2026-04", status: "PROCESSING" },
  });
  const token = mockAuthAs({ sub: "super-payout-4", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const first = await request(app)
    .post(`/api/payouts/${payoutA.id}/complete`)
    .set("Authorization", `Bearer ${token}`)
    .send({ transactionId: "shared-ref-999" });
  assert.equal(first.status, 200);

  const second = await request(app)
    .post(`/api/payouts/${payoutB.id}/complete`)
    .set("Authorization", `Bearer ${token}`)
    .send({ transactionId: "shared-ref-999" });
  assert.equal(second.status, 409);
});

test("GET /payouts (Admin) filters by a validated status enum, rejecting garbage", async () => {
  const token = mockAuthAs({ sub: "admin-sub-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .get("/api/payouts")
    .query({ status: "NOT_A_REAL_STATUS" })
    .set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 400);
});
