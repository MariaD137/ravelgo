import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("GET /api/settings/payment returns the ₦15,000 default with no setup needed", async () => {
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });
  const res = await request(app).get("/api/settings/payment").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.cashPaymentLimit, 15000);
  assert.equal(res.body.cashPaymentEnabled, true);
  assert.equal(res.body.currency, "NGN");
});

test("PATCH /api/admin/settings/payment is rejected for a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });
  const res = await request(app)
    .patch("/api/admin/settings/payment")
    .set("Authorization", `Bearer ${token}`)
    .send({ cashPaymentLimit: 20000 });
  assert.equal(res.status, 403);
});

test("PATCH /api/admin/settings/payment is rejected for a Finance admin (Super Admin only)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "finance-1", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "f@example.com" },
  });
  const token = mockAuthAs({ sub: "finance-1", groups: ["Admin"] });
  const res = await request(app)
    .patch("/api/admin/settings/payment")
    .set("Authorization", `Bearer ${token}`)
    .send({ cashPaymentLimit: 20000 });
  assert.equal(res.status, 403);
});

test("PATCH /api/admin/settings/payment lets a Super Admin change the cash limit and records an audit entry", async () => {
  const token = mockAuthAs({ sub: "super-1", groups: ["Admin"] }); // no User row -> defaults to SUPER_ADMIN
  const res = await request(app)
    .patch("/api/admin/settings/payment")
    .set("Authorization", `Bearer ${token}`)
    .send({ cashPaymentLimit: 20000 });

  assert.equal(res.status, 200);
  assert.equal(res.body.cashPaymentLimit, 20000);

  const audit = await prisma.auditLog.findFirst({ where: { action: "PAYMENT_SETTING_CHANGED" } });
  assert.ok(audit);
  const metadata = audit!.metadata as { field: string; oldValue: number; newValue: number };
  assert.equal(metadata.field, "cashPaymentLimit");
  assert.equal(metadata.oldValue, 15000);
  assert.equal(metadata.newValue, 20000);

  // The new limit takes effect immediately for the public read.
  const read = await request(app).get("/api/settings/payment").set("Authorization", `Bearer ${token}`);
  assert.equal(read.body.cashPaymentLimit, 20000);
});

test("disabling cash entirely blocks it even for a fare under the limit", async () => {
  const superToken = mockAuthAs({ sub: "super-1", groups: ["Admin"] });
  const disable = await request(app)
    .patch("/api/admin/settings/payment")
    .set("Authorization", `Bearer ${superToken}`)
    .send({ cashPaymentEnabled: false });
  assert.equal(disable.status, 200);
  assert.equal(disable.body.cashPaymentEnabled, false);

  restoreAuth();
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-2", role: "RIDER", firstName: "A", lastName: "B", email: "a2@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-2", role: "DRIVER", firstName: "C", lastName: "D", email: "c2@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "A", destination: "B", estimatedFare: 1000, finalFare: 1000, status: "COMPLETED" },
  });

  const driverToken = mockAuthAs({ sub: "driver-2", groups: ["Driver"] });
  const charge = await request(app)
    .post(`/api/trips/${trip.id}/charge`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ method: "CASH" });
  assert.equal(charge.status, 400);
});

test("POST /api/admin/cash-remittances is allowed for Finance and audited", async () => {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-3", role: "DRIVER", firstName: "C", lastName: "D", email: "c3@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  await prisma.user.create({
    data: { cognitoSub: "finance-2", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "f2@example.com" },
  });

  const token = mockAuthAs({ sub: "finance-2", email: "f2@example.com", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/admin/cash-remittances")
    .set("Authorization", `Bearer ${token}`)
    .send({ driverId: driver.id, amount: 3000, note: "handed in at the depot" });

  assert.equal(res.status, 201);
  assert.equal(res.body.amount, 3000);
  assert.equal(res.body.recordedBy, "f2@example.com");

  const audit = await prisma.auditLog.findFirst({ where: { action: "CASH_REMITTANCE_RECORDED" } });
  assert.ok(audit);
});

test("POST /api/admin/cash-remittances is rejected for an Operations admin", async () => {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-4", role: "DRIVER", firstName: "C", lastName: "D", email: "c4@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id } });
  await prisma.user.create({
    data: { cognitoSub: "ops-1", role: "ADMIN", adminRole: "OPERATIONS_MANAGER", firstName: "O", lastName: "P", email: "o@example.com" },
  });

  const token = mockAuthAs({ sub: "ops-1", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/admin/cash-remittances")
    .set("Authorization", `Bearer ${token}`)
    .send({ driverId: driver.id, amount: 3000 });

  assert.equal(res.status, 403);
});
