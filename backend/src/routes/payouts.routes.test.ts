import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await prisma.payout.deleteMany();
  await prisma.driverBankAccount.deleteMany();
  await resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.payout.deleteMany();
  await prisma.driverBankAccount.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  return user;
}

const bankAccountPayload = {
  accountHolderName: "Jane Driver",
  bankName: "First Bank",
  accountNumber: "12345678",
  routingNumber: "123456789",
};

test("POST /api/payouts/bank-account lets the calling driver register their own bank account", async () => {
  const user = await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);

  assert.equal(res.status, 201);
  assert.equal(res.body.driverId, user.id);
  assert.equal(res.body.accountHolderName, "Jane Driver");

  const stored = await prisma.driverBankAccount.findUnique({ where: { driverId: user.id } });
  assert.ok(stored);
});

test("GET /api/payouts/bank-account returns the calling driver's own bank account", async () => {
  const user = await createDriver("driver-sub-2");
  await prisma.driverBankAccount.create({ data: { driverId: user.id, ...bankAccountPayload } });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.driverId, user.id);
});

test("GET /api/payouts/history returns only the calling driver's own payouts", async () => {
  const driverA = await createDriver("driver-sub-3");
  const driverB = await createDriver("driver-sub-4");
  await prisma.payout.create({ data: { driverId: driverA.id, amount: 100, period: "2026-07", status: "PENDING" } });
  await prisma.payout.create({ data: { driverId: driverB.id, amount: 200, period: "2026-07", status: "PENDING" } });

  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].driverId, driverA.id);
  assert.equal(res.body.data[0].amount, 100);
});

test("GET /api/payouts/:id lets the calling driver retrieve their own payout", async () => {
  const driver = await createDriver("driver-sub-5");
  const payout = await prisma.payout.create({
    data: { driverId: driver.id, amount: 150, period: "2026-07", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "driver-sub-5", groups: ["Driver"] });
  const res = await request(app).get(`/api/payouts/${payout.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.id, payout.id);
});

test("GET /api/payouts/:id 404s when the payout belongs to a different driver", async () => {
  const driverA = await createDriver("driver-sub-6");
  const driverB = await createDriver("driver-sub-7");
  const payout = await prisma.payout.create({
    data: { driverId: driverB.id, amount: 300, period: "2026-07", status: "PENDING" },
  });

  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });
  const res = await request(app).get(`/api/payouts/${payout.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
  void driverA;
});

test("Payout endpoints reject a caller with a valid token but no matching User row", async () => {
  const token = mockAuthAs({ sub: "cognito-sub-with-no-user-row", groups: ["Driver"] });

  const bankAccountRes = await request(app)
    .get("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(bankAccountRes.status, 404);

  const historyRes = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${token}`);
  assert.equal(historyRes.status, 404);
});

test("Payout endpoints 404 for a User row that exists but has no Driver relationship (wrong role)", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "rider-sub-in-driver-group",
      role: "RIDER",
      firstName: "R",
      lastName: "I",
      email: "rider-sub-in-driver-group@example.com",
    },
  });
  const token = mockAuthAs({ sub: "rider-sub-in-driver-group", groups: ["Driver"] });

  const res = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("POST /api/payouts/bank-account requires auth", async () => {
  const res = await request(app).post("/api/payouts/bank-account").send(bankAccountPayload);
  assert.equal(res.status, 401);
});

test("POST /api/payouts/bank-account rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);
  assert.equal(res.status, 403);
});
