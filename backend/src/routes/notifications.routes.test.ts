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

test("POST /api/notifications/device-tokens registers a token under the authenticated caller, never a client-supplied user", async () => {
  const me = await prisma.user.create({
    data: { cognitoSub: "device-me", role: "RIDER", firstName: "M", lastName: "N", email: "devicemine@example.com" },
  });
  const token = mockAuthAs({ sub: "device-me", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/notifications/device-tokens")
    .set("Authorization", `Bearer ${token}`)
    // userId is not a real field on this schema, but even if a client sends
    // one it must be ignored — ownership only ever comes from the JWT.
    .send({ token: "fcm-token-abc", platform: "ANDROID", userId: "someone-elses-id" });

  assert.equal(res.status, 201);
  assert.equal(res.body.platform, "ANDROID");

  const stored = await prisma.pushToken.findUnique({ where: { token: "fcm-token-abc" } });
  assert.equal(stored?.userId, me.id);
});

test("POST /api/notifications/device-tokens rejects an invalid platform", async () => {
  await prisma.user.create({
    data: { cognitoSub: "device-bad-platform", role: "RIDER", firstName: "O", lastName: "P", email: "devicebad@example.com" },
  });
  const token = mockAuthAs({ sub: "device-bad-platform", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/notifications/device-tokens")
    .set("Authorization", `Bearer ${token}`)
    .send({ token: "some-token", platform: "WINDOWS_PHONE" });

  assert.equal(res.status, 400);
});

test("POST /api/notifications/device-tokens reassigns an already-known token to whoever registers it now", async () => {
  const first = await prisma.user.create({
    data: { cognitoSub: "device-first-owner", role: "RIDER", firstName: "Q", lastName: "R", email: "devicefirst@example.com" },
  });
  const second = await prisma.user.create({
    data: { cognitoSub: "device-second-owner", role: "RIDER", firstName: "S", lastName: "T", email: "devicesecond@example.com" },
  });
  await prisma.pushToken.create({ data: { userId: first.id, token: "shared-device-token", platform: "IOS" } });

  const token = mockAuthAs({ sub: "device-second-owner", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/notifications/device-tokens")
    .set("Authorization", `Bearer ${token}`)
    .send({ token: "shared-device-token", platform: "IOS" });

  assert.equal(res.status, 201);
  const stored = await prisma.pushToken.findUnique({ where: { token: "shared-device-token" } });
  assert.equal(stored?.userId, second.id);
  // Reassigned, not duplicated — token is @unique, so this also proves no
  // second row was created for the same token.
  assert.equal(await prisma.pushToken.count({ where: { token: "shared-device-token" } }), 1);
});

test("DELETE /api/notifications/device-tokens enforces ownership and removes the token", async () => {
  const owner = await prisma.user.create({
    data: { cognitoSub: "device-del-owner", role: "RIDER", firstName: "U", lastName: "V", email: "devicedel@example.com" },
  });
  await prisma.user.create({
    data: { cognitoSub: "device-del-stranger", role: "RIDER", firstName: "W", lastName: "X", email: "devicedelstranger@example.com" },
  });
  await prisma.pushToken.create({ data: { userId: owner.id, token: "token-to-delete", platform: "ANDROID" } });

  const strangerToken = mockAuthAs({ sub: "device-del-stranger", groups: ["Rider"] });
  const deniedRes = await request(app)
    .delete("/api/notifications/device-tokens")
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ token: "token-to-delete" });
  assert.equal(deniedRes.status, 404);
  assert.ok(await prisma.pushToken.findUnique({ where: { token: "token-to-delete" } }));

  restoreAuth();
  const ownerToken = mockAuthAs({ sub: "device-del-owner", groups: ["Rider"] });
  const okRes = await request(app)
    .delete("/api/notifications/device-tokens")
    .set("Authorization", `Bearer ${ownerToken}`)
    .send({ token: "token-to-delete" });
  assert.equal(okRes.status, 204);
  assert.equal(await prisma.pushToken.findUnique({ where: { token: "token-to-delete" } }), null);
});
