import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

// Admin list pagination (A-1). The Admin App pages through every list with
// page/pageSize and the additive totalPages/hasNext metadata; server-side
// filters must apply across the whole table, not within one page; and the
// backend maximum page size stays 100.

beforeEach(() => resetDb());
afterEach(() => restoreAuth());
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

const admin = () => mockAuthAs({ sub: "pagination-admin", groups: ["Admin"] });

async function seedRiders(n: number) {
  await prisma.user.createMany({
    data: Array.from({ length: n }, (_, i) => ({
      cognitoSub: `pg-rider-${i}`,
      role: "RIDER" as const,
      firstName: "Rider",
      lastName: `${i}`,
      email: `pg-rider-${i}@example.com`,
    })),
  });
}

test("first page, second page and the metadata for a table larger than the 100-row maximum", async () => {
  await seedRiders(120);
  const token = admin();

  const first = await request(app).get("/api/riders?page=1&pageSize=50").set("Authorization", `Bearer ${token}`);
  assert.equal(first.status, 200);
  assert.equal(first.body.data.length, 50);
  assert.equal(first.body.page, 1);
  assert.equal(first.body.pageSize, 50);
  assert.equal(first.body.total, 120);
  assert.equal(first.body.totalPages, 3);
  assert.equal(first.body.hasNext, true);

  const second = await request(app).get("/api/riders?page=2&pageSize=50").set("Authorization", `Bearer ${token}`);
  assert.equal(second.body.data.length, 50);
  assert.equal(second.body.hasNext, true);
  // No overlap between pages.
  const firstIds = new Set(first.body.data.map((r: { id: string }) => r.id));
  assert.ok(second.body.data.every((r: { id: string }) => !firstIds.has(r.id)));

  const last = await request(app).get("/api/riders?page=3&pageSize=50").set("Authorization", `Bearer ${token}`);
  assert.equal(last.body.data.length, 20);
  assert.equal(last.body.hasNext, false);

  // A page past the end is an empty page, not an error, and the metadata still says where the end is.
  const beyond = await request(app).get("/api/riders?page=4&pageSize=50").set("Authorization", `Bearer ${token}`);
  assert.equal(beyond.status, 200);
  assert.deepEqual(beyond.body.data, []);
  assert.equal(beyond.body.totalPages, 3);

  // Default page size and the hard ceiling are unchanged.
  const dflt = await request(app).get("/api/riders").set("Authorization", `Bearer ${token}`);
  assert.equal(dflt.body.pageSize, 20);
  const tooBig = await request(app).get("/api/riders?pageSize=101").set("Authorization", `Bearer ${token}`);
  assert.equal(tooBig.status, 400);
});

test("an empty table paginates as one empty page", async () => {
  const token = admin();
  const res = await request(app).get("/api/riders?pageSize=25").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.data, []);
  assert.equal(res.body.total, 0);
  assert.equal(res.body.totalPages, 1);
  assert.equal(res.body.hasNext, false);
});

test("a mutation is reflected on the next fetch of the same page", async () => {
  await seedRiders(3);
  const token = admin();
  const before = await request(app).get("/api/riders?pageSize=10").set("Authorization", `Bearer ${token}`);
  const target = before.body.data[0];
  assert.equal(target.suspended, false);

  const patch = await request(app)
    .patch(`/api/riders/${target.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: true });
  assert.equal(patch.status, 200);

  const after = await request(app).get("/api/riders?pageSize=10").set("Authorization", `Bearer ${token}`);
  const refreshed = after.body.data.find((r: { id: string }) => r.id === target.id);
  assert.equal(refreshed.suspended, true);
});

test("GET /trips filters by one or several statuses server-side, combined with pagination", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "pg-trip-rider", role: "RIDER", firstName: "R", lastName: "T", email: "pg-trip-rider@example.com" },
  });
  const statuses = ["REQUESTED", "MATCHED", "IN_PROGRESS", "COMPLETED", "CANCELLED"] as const;
  for (let i = 0; i < 25; i++) {
    await prisma.trip.create({
      data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 10, status: statuses[i % statuses.length] },
    });
  }
  const token = admin();

  const completed = await request(app).get("/api/trips?status=COMPLETED&pageSize=3").set("Authorization", `Bearer ${token}`);
  assert.equal(completed.status, 200);
  assert.equal(completed.body.total, 5);
  assert.equal(completed.body.totalPages, 2);
  assert.ok(completed.body.data.every((t: { status: string }) => t.status === "COMPLETED"));

  const active = await request(app)
    .get("/api/trips?status=MATCHED,IN_PROGRESS&pageSize=100")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(active.body.total, 10);
  assert.ok(active.body.data.every((t: { status: string }) => t.status === "MATCHED" || t.status === "IN_PROGRESS"));

  const all = await request(app).get("/api/trips?pageSize=100").set("Authorization", `Bearer ${token}`);
  assert.equal(all.body.total, 25);

  const bad = await request(app).get("/api/trips?status=NOT_A_STATUS").set("Authorization", `Bearer ${token}`);
  assert.equal(bad.status, 400);
});

test("GET /courier-requests filters by status server-side", async () => {
  const sender = await prisma.user.create({
    data: { cognitoSub: "pg-sender", role: "RIDER", firstName: "S", lastName: "N", email: "pg-sender@example.com" },
  });
  for (const status of ["REQUESTED", "REQUESTED", "DELIVERED"] as const) {
    await prisma.courierRequest.create({
      data: {
        senderId: sender.id,
        pickupAddress: "A",
        dropoffAddress: "B",
        recipientName: "R",
        recipientPhone: "0",
        packageDescription: "box",
        packageSize: "SMALL",
        estimatedFare: 5,
        status,
      },
    });
  }
  const token = admin();
  const res = await request(app).get("/api/courier-requests?status=REQUESTED").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.total, 2);
  assert.ok(res.body.data.every((c: { status: string }) => c.status === "REQUESTED"));
});

test("GET /emergency-alerts filters by type (one screen per type) and pages within that type", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "pg-alert-user", role: "RIDER", firstName: "A", lastName: "L", email: "pg-alert@example.com" },
  });
  await prisma.emergencyAlert.createMany({
    data: [
      ...Array.from({ length: 4 }, () => ({ userId: user.id, type: "SOS" as const })),
      ...Array.from({ length: 6 }, () => ({ userId: user.id, type: "FRAUD_SUSPECTED" as const })),
    ],
  });
  const token = admin();
  const sos = await request(app).get("/api/emergency-alerts?type=SOS&pageSize=3").set("Authorization", `Bearer ${token}`);
  assert.equal(sos.status, 200);
  assert.equal(sos.body.total, 4);
  assert.equal(sos.body.totalPages, 2);
  assert.ok(sos.body.data.every((a: { type: string }) => a.type === "SOS"));

  const fraud = await request(app).get("/api/emergency-alerts?type=FRAUD_SUSPECTED").set("Authorization", `Bearer ${token}`);
  assert.equal(fraud.body.total, 6);

  const bad = await request(app).get("/api/emergency-alerts?type=OTHER").set("Authorization", `Bearer ${token}`);
  assert.equal(bad.status, 400);
});

test("GET /payments returns whole-table SUCCEEDED totals per method alongside the page", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "pg-pay-rider", role: "RIDER", firstName: "P", lastName: "Y", email: "pg-pay@example.com" },
  });
  const rows = [
    { method: "CASH", status: "SUCCEEDED", amount: 100 },
    { method: "CASH", status: "SUCCEEDED", amount: 50 },
    { method: "CARD", status: "SUCCEEDED", amount: 70 },
    { method: "CARD", status: "FAILED", amount: 999 },
    { method: "WALLET", status: "SUCCEEDED", amount: 30 },
    { method: "WALLET", status: "REFUNDED", amount: 500 },
  ] as const;
  for (const row of rows) {
    const trip = await prisma.trip.create({
      data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: row.amount, status: "COMPLETED" },
    });
    await prisma.payment.create({
      data: { tripId: trip.id, userId: rider.id, amount: row.amount, method: row.method, status: row.status },
    });
  }
  const token = admin();
  const res = await request(app).get("/api/payments?pageSize=2").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 2);
  assert.equal(res.body.total, 6);
  assert.equal(res.body.totalPages, 3);
  assert.deepEqual(res.body.totals, { cash: 150, card: 70, wallet: 30 });
});
