import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";
import { withBypass } from "../lib/rls";

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
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  return { user, driver };
}

const bankAccountPayload = {
  accountHolderName: "Dana Driver",
  bankName: "First Bank",
  accountNumber: "000123456789",
  routingNumber: "021000021",
};

test("POST /api/payouts/bank-account creates the account and masks the response", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);

  assert.equal(res.status, 201);
  assert.equal(res.body.accountNumber, "****6789");
  assert.equal(res.body.routingNumber, "****0021");

  const stored = await withBypass((tx) => tx.driverBankAccount.findFirst());
  assert.ok(stored);
  assert.notEqual(stored!.accountNumber, bankAccountPayload.accountNumber);
  assert.notEqual(stored!.routingNumber, bankAccountPayload.routingNumber);
});

// Regression test: driverId is a FK to User.id, not the Cognito sub — an
// earlier version of this route used req.user!.sub directly, so a GET
// right after a successful POST would 404 (findUnique never matched).
test("GET /api/payouts/bank-account finds the account the same driver just created", async () => {
  await createDriver("driver-sub-2");
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });

  const postRes = await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${token}`)
    .send(bankAccountPayload);
  assert.equal(postRes.status, 201);

  const getRes = await request(app).get("/api/payouts/bank-account").set("Authorization", `Bearer ${token}`);
  assert.equal(getRes.status, 200);
  assert.equal(getRes.body.accountNumber, "****6789");
  assert.equal(getRes.body.accountHolderName, "Dana Driver");
});

test("GET /api/payouts/history only returns the calling driver's own payouts", async () => {
  const { user: driverA } = await createDriver("driver-sub-3");
  const { user: driverB } = await createDriver("driver-sub-4");
  await withBypass((tx) => tx.payout.create({ data: { driverId: driverA.id, amount: 100, period: "2026-07", status: "PENDING" } }));
  await withBypass((tx) => tx.payout.create({ data: { driverId: driverB.id, amount: 200, period: "2026-07", status: "PENDING" } }));

  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/payouts/history").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data[0].amount, 100);
});

test("Admin: POST /api/payouts/create with an override amount masks bank details in the response", async () => {
  const { user: driver } = await createDriver("driver-sub-5");
  const driverToken = mockAuthAs({ sub: "driver-sub-5", groups: ["Driver"] });
  await request(app)
    .post("/api/payouts/bank-account")
    .set("Authorization", `Bearer ${driverToken}`)
    .send(bankAccountPayload);
  restoreAuth();

  const adminToken = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .post("/api/payouts/create")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ driverId: driver.id, period: "2026-08", amount: 150, reason: "manual test payout" });

  assert.equal(res.status, 201);
  assert.equal(res.body.amount, 150);
});
