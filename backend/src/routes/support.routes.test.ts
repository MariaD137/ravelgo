import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAdminUserStatus } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("POST /api/support-tickets creates a ticket owned by the calling user", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/support-tickets")
    .set("Authorization", `Bearer ${token}`)
    .send({ subject: "Lost item", category: "Trip" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "OPEN");
});

test("GET /api/support-tickets/mine only returns the caller's own tickets", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "rider-sub-2", role: "RIDER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const other = await prisma.user.create({
    data: { cognitoSub: "rider-sub-3", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  await prisma.supportTicket.create({ data: { userId: me.id, subject: "Mine", category: "Billing" } });
  await prisma.supportTicket.create({ data: { userId: other.id, subject: "Not mine", category: "Billing" } });

  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const res = await request(app).get("/api/support-tickets/mine").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].subject, "Mine");
});

test("GET /api/support-tickets/mine scopes correctly for a Driver caller too — a driver never sees another driver's ticket", async () => {
  const driverA = await prisma.user.create({
    data: { cognitoSub: "driver-support-a", role: "DRIVER", firstName: "A", lastName: "D", email: "drva@example.com" },
  });
  const driverB = await prisma.user.create({
    data: { cognitoSub: "driver-support-b", role: "DRIVER", firstName: "B", lastName: "D", email: "drvb@example.com" },
  });
  await prisma.supportTicket.create({ data: { userId: driverA.id, subject: "Trip dispute", category: "Trip or delivery dispute" } });
  await prisma.supportTicket.create({ data: { userId: driverB.id, subject: "Not mine", category: "App issue" } });

  const tokenA = mockAuthAs({ sub: "driver-support-a", groups: ["Driver"] });
  const createRes = await request(app)
    .post("/api/support-tickets")
    .set("Authorization", `Bearer ${tokenA}`)
    .send({ subject: "New issue", category: "Payment or earnings issue" });
  assert.equal(createRes.status, 201);

  const res = await request(app).get("/api/support-tickets/mine").set("Authorization", `Bearer ${tokenA}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.length, 2);
  assert.ok(res.body.every((t: { subject: string }) => t.subject !== "Not mine"));
});

test("GET /api/support-tickets rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const res = await request(app).get("/api/support-tickets").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/support-tickets/:id/status lets an Admin resolve a ticket", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "rider-sub-5", role: "RIDER", firstName: "G", lastName: "H", email: "g@example.com" },
  });
  const ticket = await prisma.supportTicket.create({ data: { userId: user.id, subject: "Issue", category: "App" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch(`/api/support-tickets/${ticket.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "RESOLVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "RESOLVED");
});
