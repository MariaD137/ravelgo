import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.driverSubscription.deleteMany();
  await prisma.subscriptionPlan.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.driverSubscription.deleteMany();
  await prisma.subscriptionPlan.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id } });
}

test("POST /api/subscription-plans rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/subscription-plans")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Pro", description: "Priority matching", priceMonthly: 29 });
  assert.equal(res.status, 403);
});

test("POST /api/subscription-plans lets an Admin create a plan, then it's listed publicly", async () => {
  const adminToken = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const create = await request(app)
    .post("/api/subscription-plans")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ name: "Pro", description: "Priority matching", priceMonthly: 29 });
  assert.equal(create.status, 201);

  restoreAuth();
  const driverToken = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const list = await request(app).get("/api/subscription-plans").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 1);
  assert.equal(list.body[0].name, "Pro");

  const audit = await prisma.auditLog.findFirst({ where: { action: "SUBSCRIPTION_PLAN_CREATED", entityId: create.body.id } });
  assert.ok(audit);
});

test("POST /api/subscription-plans rejects a Finance Viewer admin", async () => {
  await prisma.user.create({
    data: { cognitoSub: "finance-plans", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "fv-plans@example.com" },
  });
  const token = mockAuthAs({ sub: "finance-plans", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/subscription-plans")
    .set("Authorization", `Bearer ${token}`)
    .send({ name: "Pro", description: "Priority matching", priceMonthly: 29 });
  assert.equal(res.status, 403);
});

test("POST /api/drivers/me/subscription subscribes the calling driver and flips subscriptionActive", async () => {
  const driver = await createDriver("driver-sub-3");
  const plan = await prisma.subscriptionPlan.create({
    data: { name: "Basic", description: "Standard", priceMonthly: 9 },
  });

  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/drivers/me/subscription")
    .set("Authorization", `Bearer ${token}`)
    .send({ planId: plan.id, currentPeriodEnd: new Date(Date.now() + 30 * 86400000).toISOString() });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "ACTIVE");

  const updatedDriver = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(updatedDriver?.subscriptionActive, true);
});

test("DELETE /api/drivers/me/subscription cancels it and flips subscriptionActive off", async () => {
  const driver = await createDriver("driver-sub-4");
  const plan = await prisma.subscriptionPlan.create({
    data: { name: "Basic2", description: "Standard", priceMonthly: 9 },
  });
  await prisma.driverSubscription.create({
    data: { driverId: driver.id, planId: plan.id, currentPeriodEnd: new Date(Date.now() + 30 * 86400000) },
  });
  await prisma.driver.update({ where: { id: driver.id }, data: { subscriptionActive: true } });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app).delete("/api/drivers/me/subscription").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "CANCELLED");

  const updatedDriver = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(updatedDriver?.subscriptionActive, false);
});
