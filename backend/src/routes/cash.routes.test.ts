import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import { randomUUID } from "node:crypto";
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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id } });
}

// The row cap the route enforces (see cash.routes.ts's CASH_ROW_CAP) —
// duplicated here rather than imported so this test proves the CONTRACT
// (whatever the cap is, truncation is reported correctly around it), not an
// internal constant.
const CASH_ROW_CAP = 5000;

function ledgerRow(driverId: string) {
  return {
    type: "RIDE_FARE" as const,
    customerId: randomUUID(),
    driverId,
    grossAmount: 1000,
    commissionRate: 0.2,
    commissionAmount: 200,
    driverEarnings: 800,
    paymentMethod: "CASH" as const,
    status: "SETTLED" as const,
  };
}

test("GET /api/admin/cash-reconciliation reports truncated:false when the ledger is under the cap", async () => {
  const driver = await createDriver("driver-sub-cash-1");
  await prisma.financialTransaction.createMany({
    data: Array.from({ length: 3 }, () => ledgerRow(driver.id)),
  });

  const token = mockAuthAs({ sub: "admin-sub-cash-1", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/cash-reconciliation").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.truncated, false);
  assert.equal(res.body.ledgerRowCount, 3);
  assert.equal(res.body.remittanceRowCount, 0);
  const row = res.body.rows.find((r: { driverId: string }) => r.driverId === driver.id);
  // 3 CASH rides at 200 commission each = 600 expected, computed from the
  // real ledger rows — not a client-asserted or estimated figure.
  assert.equal(row.expectedCash, 600);
  assert.equal(row.cashTripCount, 3);
});

test("GET /api/admin/cash-reconciliation reports truncated:false at exactly the cap", async () => {
  const driver = await createDriver("driver-sub-cash-2");
  await prisma.financialTransaction.createMany({
    data: Array.from({ length: CASH_ROW_CAP }, () => ledgerRow(driver.id)),
  });

  const token = mockAuthAs({ sub: "admin-sub-cash-2", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/cash-reconciliation").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.truncated, false);
  assert.equal(res.body.ledgerRowCount, CASH_ROW_CAP);
});

test("GET /api/admin/cash-reconciliation reports truncated:true above the cap, without misreporting the count", async () => {
  const driver = await createDriver("driver-sub-cash-3");
  await prisma.financialTransaction.createMany({
    data: Array.from({ length: CASH_ROW_CAP + 7 }, () => ledgerRow(driver.id)),
  });

  const token = mockAuthAs({ sub: "admin-sub-cash-3", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/cash-reconciliation").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.truncated, true);
  // The COUNT is always exact (a separate, uncapped query) even though the
  // per-driver totals below it are computed from only the first CASH_ROW_CAP
  // rows fetched — this is exactly what "truncated" exists to flag.
  assert.equal(res.body.ledgerRowCount, CASH_ROW_CAP + 7);
});

test("a suspended admin cannot read cash reconciliation", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "suspended-cash-admin",
      role: "ADMIN",
      suspended: true,
      firstName: "S",
      lastName: "A",
      email: "suspended-cash@example.com",
    },
  });
  const token = mockAuthAs({ sub: "suspended-cash-admin", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/cash-reconciliation").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
