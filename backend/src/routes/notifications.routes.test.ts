import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";
import { notifyUser } from "../lib/notifications";

beforeEach(async () => {
  await resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("GET /api/notifications returns only the caller's own notifications, newest first, with an unread count", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "notif-me", role: "RIDER", firstName: "A", lastName: "B", email: "notifme@example.com" },
  });
  const someoneElse = await prisma.user.create({
    data: { cognitoSub: "notif-other", role: "RIDER", firstName: "C", lastName: "D", email: "notifother@example.com" },
  });

  await notifyUser(someoneElse.id, "RIDE_STARTED", "Not mine", "Should never appear for me");
  await notifyUser(me.id, "RIDE_DRIVER_ASSIGNED", "Driver assigned", "First", { type: "TRIP", id: "trip-1" });
  await notifyUser(me.id, "RIDE_COMPLETED", "Ride completed", "Second", { type: "TRIP", id: "trip-1" });

  const token = mockAuthAs({ sub: "notif-me", groups: ["Rider"] });
  const res = await request(app).get("/api/notifications").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 2);
  assert.equal(res.body.unreadCount, 2);
  assert.equal(res.body.data[0].title, "Ride completed"); // newest first
  assert.ok(res.body.data.every((n: { userId: string }) => n.userId === me.id));
});

test("PATCH /api/notifications/:id/read enforces ownership and marks read", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "notif-owner", role: "RIDER", firstName: "E", lastName: "F", email: "owner@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "notif-stranger", role: "RIDER", firstName: "G", lastName: "H", email: "stranger@example.com" },
  });
  const notification = await prisma.notification.create({
    data: { userId: me.id, type: "RIDE_COMPLETED", title: "T", body: "B" },
  });

  const strangerToken = mockAuthAs({ sub: "notif-stranger", groups: ["Rider"] });
  const deniedRes = await request(app)
    .patch(`/api/notifications/${notification.id}/read`)
    .set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(deniedRes.status, 404); // not 403 — never confirms the id belongs to someone else

  restoreAuth();
  const ownerToken = mockAuthAs({ sub: "notif-owner", groups: ["Rider"] });
  const okRes = await request(app)
    .patch(`/api/notifications/${notification.id}/read`)
    .set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(okRes.status, 200);
  assert.equal(okRes.body.read, true);
});

test("POST /api/notifications/read-all marks only the caller's unread notifications as read", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "notif-all-me", role: "RIDER", firstName: "I", lastName: "J", email: "allme@example.com" },
  });
  const someoneElse = await prisma.user.create({
    data: { cognitoSub: "notif-all-other", role: "RIDER", firstName: "K", lastName: "L", email: "allother@example.com" },
  });
  await notifyUser(me.id, "RIDE_STARTED", "T1", "B1");
  await notifyUser(me.id, "RIDE_COMPLETED", "T2", "B2");
  await notifyUser(someoneElse.id, "RIDE_STARTED", "T3", "B3");

  const token = mockAuthAs({ sub: "notif-all-me", groups: ["Rider"] });
  const res = await request(app).post("/api/notifications/read-all").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.updated, 2);

  const otherStillUnread = await prisma.notification.findFirst({ where: { userId: someoneElse.id } });
  assert.equal(otherStillUnread?.read, false);
});
