import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAddToGroup, mockCognitoAdminUserStatus } from "../test/helpers";
import { getLatestDriverLocation, resetRealtimeState } from "../realtime/hub";

beforeEach(() => {
  resetRealtimeState();
  return resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// P0 #2 — server-authoritative driver onboarding. The Driver role is granted
// by the SERVER (Cognito AdminAddUserToGroup), never self-assigned by a client.

test("POST /api/drivers/apply lets any authenticated user apply and grants the Driver group server-side", async () => {
  // A plain signed-up user — only in the Rider group, NOT already a Driver.
  const token = mockAuthAs({ sub: "applicant-1", groups: ["Rider"] });
  const addToGroup = mockCognitoAddToGroup();

  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Ada", lastName: "N", email: "ada@example.com" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  // The role grant went through the SERVER, with the caller's sub + Driver group.
  assert.equal(addToGroup.mock.callCount(), 1);
  assert.deepEqual(addToGroup.mock.calls[0].arguments, ["applicant-1", "Driver"]);

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: "applicant-1" } } });
  assert.ok(driver);
});

test("POST /api/drivers/apply requires authentication", async () => {
  const res = await request(app)
    .post("/api/drivers/apply")
    .send({ firstName: "No", lastName: "Auth", email: "noauth@example.com" });
  assert.equal(res.status, 401);
});

test("POST /api/drivers/apply is idempotent — re-applying returns the existing profile, no duplicate", async () => {
  const token = mockAuthAs({ sub: "applicant-2", groups: ["Rider"] });
  mockCognitoAddToGroup();

  const first = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Rex", lastName: "T", email: "rex@example.com" });
  assert.equal(first.status, 201);

  const second = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Rex", lastName: "T", email: "rex@example.com" });
  assert.equal(second.status, 200);
  assert.equal(second.body.id, first.body.id);

  const count = await prisma.driver.count({ where: { user: { cognitoSub: "applicant-2" } } });
  assert.equal(count, 1);
});

test("POST /api/drivers/apply does NOT report success when the Cognito group grant fails", async () => {
  const token = mockAuthAs({ sub: "applicant-3", groups: ["Rider"] });
  mockCognitoAddToGroup({ shouldThrow: true });

  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Fai", lastName: "L", email: "fail@example.com" });

  // The role never took effect, so the caller must not be told it worked.
  assert.equal(res.status, 502);
});

test("POST /api/drivers/apply is server-authoritative — a rider cannot reach Driver-only routes without it", async () => {
  // Before applying, a Rider-group token is rejected by a Driver-only route.
  const token = mockAuthAs({ sub: "applicant-4", groups: ["Rider"] });
  const blocked = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(blocked.status, 403);
});

test("POST /api/drivers/apply never downgrades an ADMIN's User.role, and the admin keeps admin access and stays listed", async () => {
  const admin = await prisma.user.create({
    data: {
      cognitoSub: "admin-applies-sub",
      role: "ADMIN",
      adminRole: "OPERATIONS_MANAGER",
      firstName: "Ops",
      lastName: "Admin",
      email: "ops-admin@example.com",
    },
  });
  mockCognitoAddToGroup();
  // The admin's token is what they'd carry into the Driver App: Admin group only.
  const adminToken = mockAuthAs({ sub: "admin-applies-sub", email: "ops-admin@example.com", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ firstName: "Placeholder", lastName: "Name", email: "ops-admin@example.com" });
  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  // The row is untouched: still ADMIN, preset intact, name not clobbered.
  const after = await prisma.user.findUnique({ where: { id: admin.id } });
  assert.equal(after?.role, "ADMIN");
  assert.equal(after?.adminRole, "OPERATIONS_MANAGER");
  assert.equal(after?.firstName, "Ops");

  // A Driver profile exists for them, in PENDING_REVIEW like any applicant.
  const driver = await prisma.driver.findUnique({ where: { userId: admin.id } });
  assert.equal(driver?.status, "PENDING_REVIEW");

  // Admin access is unchanged: base Admin gate and the drivers:write preset check
  // (which reads adminRole/suspended from this very row) both still pass.
  const dashboard = await request(app).get("/api/admin/dashboard").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(dashboard.status, 200);
  const suspend = await request(app)
    .patch(`/api/drivers/${driver!.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "SUSPENDED" });
  assert.equal(suspend.status, 200);

  // And they remain visible to admin-user management (which filters on role === ADMIN).
  const superAdminToken = mockAuthAs({ sub: "super-admin-lister-sub", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const listed = await request(app).get("/api/admin-users").set("Authorization", `Bearer ${superAdminToken}`);
  assert.equal(listed.status, 200);
  assert.ok(listed.body.some((u: { id: string }) => u.id === admin.id));
  const detail = await request(app).get(`/api/admin-users/${admin.id}`).set("Authorization", `Bearer ${superAdminToken}`);
  assert.equal(detail.status, 200);

  // A DRIVER-group applicant still does not get that treatment: a rider's row
  // becomes DRIVER exactly as before.
  const riderToken = mockAuthAs({ sub: "rider-applies-sub", email: "rider-applies@example.com", groups: ["Rider"] });
  await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "R", lastName: "D", email: "rider-applies@example.com" });
  const rider = await prisma.user.findUnique({ where: { cognitoSub: "rider-applies-sub" } });
  assert.equal(rider?.role, "DRIVER");
});

test("POST /api/drivers/me creates a user + driver profile together", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "Kay", lastName: "D", email: "kay@example.com" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_REVIEW");

  const user = await prisma.user.findUnique({ where: { cognitoSub: "driver-sub-1" } });
  assert.ok(user);
  assert.equal(user?.role, "DRIVER");
});

test("GET /api/drivers/me 404s before a driver profile exists", async () => {
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /api/drivers rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });
  const res = await request(app).get("/api/drivers").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/drivers/:id/status lets an Admin suspend a driver", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-4", role: "DRIVER", firstName: "Lo", lastName: "P", email: "lo@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "SUSPENDED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "SUSPENDED");

  // EI-1 gap closed: the driver must actually be told their account status
  // changed, not just have an audit row written about them.
  const notifications = await prisma.notification.findMany({ where: { userId: user.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "DRIVER_ACCOUNT_STATUS_CHANGED");
});

// ---------------------------------------------------------------------------
// Driver application -> admin approval -> driver can go online. These are the
// end-to-end contract the Driver App (GET /drivers/me, PATCH
// /drivers/me/availability) and the Admin App (PATCH /drivers/:id/status)
// both depend on: ONE field, Driver.status, read and written through ONE
// endpoint each.
// ---------------------------------------------------------------------------

async function applyAsDriver(sub: string, email: string) {
  mockCognitoAddToGroup();
  const token = mockAuthAs({ sub, email, groups: ["Rider"] });
  const res = await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "App", lastName: "Licant", email });
  assert.equal(res.status, 201);
  return res.body as { id: string; userId: string; status: string };
}

test("approval flow: apply -> PENDING_REVIEW -> admin approves -> driver reads ACTIVE and can go online", async () => {
  const driver = await applyAsDriver("e2e-driver-sub", "e2e@example.com");
  assert.equal(driver.status, "PENDING_REVIEW");

  // Before approval: the driver's own view is PENDING_REVIEW and going online is refused.
  const pendingDriverToken = mockAuthAs({ sub: "e2e-driver-sub", groups: ["Driver"] });
  const meBefore = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${pendingDriverToken}`);
  assert.equal(meBefore.status, 200);
  assert.equal(meBefore.body.status, "PENDING_REVIEW");
  const blocked = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${pendingDriverToken}`)
    .send({ isOnline: true });
  assert.equal(blocked.status, 409);

  // The admin's pending queue contains this application.
  const adminToken = mockAuthAs({ sub: "e2e-admin-sub", groups: ["Admin"] });
  const queue = await request(app).get("/api/drivers?status=PENDING_REVIEW").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(queue.status, 200);
  assert.ok(queue.body.data.some((d: { id: string }) => d.id === driver.id));

  // Admin approves.
  const approve = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(approve.status, 200);
  assert.equal(approve.body.id, driver.id);
  assert.equal(approve.body.status, "ACTIVE");

  // Database is the source of truth and it changed.
  const row = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(row?.status, "ACTIVE");

  // It left the pending queue.
  const queueAfter = await request(app).get("/api/drivers?status=PENDING_REVIEW").set("Authorization", `Bearer ${adminToken}`);
  assert.ok(!queueAfter.body.data.some((d: { id: string }) => d.id === driver.id));

  // The driver was told, with an audit trail of who did it.
  const notifications = await prisma.notification.findMany({ where: { userId: driver.userId } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "DRIVER_ACCOUNT_STATUS_CHANGED");
  assert.equal(notifications[0].title, "You're approved!");
  const audit = await prisma.auditLog.findMany({ where: { action: "DRIVER_STATUS_CHANGED", entityId: driver.id } });
  assert.equal(audit.length, 1);
  assert.equal(audit[0].actorSub, "e2e-admin-sub");

  // The driver app's next status request sees ACTIVE and the driver can go online.
  const driverToken = mockAuthAs({ sub: "e2e-driver-sub", groups: ["Driver"] });
  const meAfter = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(meAfter.body.status, "ACTIVE");
  const online = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ isOnline: true });
  assert.equal(online.status, 200);
  assert.equal(online.body.isOnline, true);
});

test("PATCH /api/drivers/:id/status is idempotent — approving an already-approved driver does not re-notify", async () => {
  const driver = await applyAsDriver("idem-driver-sub", "idem@example.com");
  const adminToken = mockAuthAs({ sub: "idem-admin-sub", groups: ["Admin"] });

  const first = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(first.status, 200);
  const second = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(second.status, 200);
  assert.equal(second.body.status, "ACTIVE");

  const notifications = await prisma.notification.findMany({ where: { userId: driver.userId } });
  assert.equal(notifications.length, 1);
  const audit = await prisma.auditLog.findMany({ where: { action: "DRIVER_STATUS_CHANGED", entityId: driver.id } });
  assert.equal(audit.length, 1);
});

test("PATCH /api/drivers/:id/status 404s for a driver that doesn't exist and 400s for an unknown status", async () => {
  const driver = await applyAsDriver("bad-status-driver-sub", "bad-status@example.com");
  const adminToken = mockAuthAs({ sub: "bad-status-admin-sub", groups: ["Admin"] });

  const missing = await request(app)
    .patch("/api/drivers/00000000-0000-0000-0000-000000000000/status")
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(missing.status, 404);

  const invalid = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "APPROVED" });
  assert.equal(invalid.status, 400);

  const untouched = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(untouched?.status, "PENDING_REVIEW");
});

test("PATCH /api/drivers/:id/status cannot be used by the driver themself, another driver, a rider, or anonymously", async () => {
  const driver = await applyAsDriver("self-approve-sub", "self@example.com");

  const selfToken = mockAuthAs({ sub: "self-approve-sub", groups: ["Driver"] });
  const self = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${selfToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(self.status, 403);

  const otherDriverToken = mockAuthAs({ sub: "other-driver-sub", groups: ["Driver"] });
  const other = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${otherDriverToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(other.status, 403);

  const riderToken = mockAuthAs({ sub: "rider-approve-sub", groups: ["Rider"] });
  const rider = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(rider.status, 403);

  const anonymous = await request(app).patch(`/api/drivers/${driver.id}/status`).send({ status: "ACTIVE" });
  assert.equal(anonymous.status, 401);

  const untouched = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(untouched?.status, "PENDING_REVIEW");
});

test("a driver cannot change their own approval status through any driver-facing endpoint", async () => {
  await applyAsDriver("escalate-sub", "escalate@example.com");
  const token = mockAuthAs({ sub: "escalate-sub", groups: ["Driver"] });

  // Client-supplied status fields are simply not part of these schemas — they
  // must be ignored (or rejected), never applied.
  await request(app)
    .post("/api/drivers/apply")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "E", lastName: "S", email: "escalate@example.com", status: "ACTIVE" });
  await request(app)
    .patch("/api/drivers/me/preferences")
    .set("Authorization", `Bearer ${token}`)
    .send({ preferredLanguage: "English", status: "ACTIVE" });
  await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: false, status: "ACTIVE" });

  const me = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(me.body.status, "PENDING_REVIEW");
});

test("a SUSPENDED driver is taken offline-eligible: going online is refused until an admin reactivates", async () => {
  const driver = await applyAsDriver("suspend-sub", "suspend@example.com");
  const adminToken = mockAuthAs({ sub: "suspend-admin-sub", groups: ["Admin"] });
  await request(app).patch(`/api/drivers/${driver.id}/status`).set("Authorization", `Bearer ${adminToken}`).send({ status: "ACTIVE" });
  const suspend = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "SUSPENDED" });
  assert.equal(suspend.status, 200);

  const driverToken = mockAuthAs({ sub: "suspend-sub", groups: ["Driver"] });
  const blocked = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ isOnline: true });
  assert.equal(blocked.status, 409);

  const reactivateToken = mockAuthAs({ sub: "suspend-admin-sub", groups: ["Admin"] });
  const reactivate = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${reactivateToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(reactivate.status, 200);
  const notifications = await prisma.notification.findMany({ where: { userId: driver.userId }, orderBy: { createdAt: "asc" } });
  assert.deepEqual(
    notifications.map((n) => n.title),
    ["You're approved!", "Account suspended", "You're approved!"],
  );
});

test("GET /api/drivers?status= filters server-side and rejects an unknown status", async () => {
  const pending = await applyAsDriver("filter-pending-sub", "filter-pending@example.com");
  const approved = await applyAsDriver("filter-approved-sub", "filter-approved@example.com");
  await prisma.driver.update({ where: { id: approved.id }, data: { status: "ACTIVE" } });

  const adminToken = mockAuthAs({ sub: "filter-admin-sub", groups: ["Admin"] });
  const pendingOnly = await request(app).get("/api/drivers?status=PENDING_REVIEW").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(pendingOnly.status, 200);
  assert.deepEqual(
    pendingOnly.body.data.map((d: { id: string }) => d.id),
    [pending.id],
  );
  assert.equal(pendingOnly.body.total, 1);

  const all = await request(app).get("/api/drivers").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(all.body.total, 2);

  const bad = await request(app).get("/api/drivers?status=APPROVED").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(bad.status, 400);
});

test("PATCH /api/drivers/:id/status rejects a Support Agent admin preset", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-5", role: "DRIVER", firstName: "Mo", lastName: "P", email: "mo@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  await prisma.user.create({
    data: { cognitoSub: "support-agent-2", role: "ADMIN", firstName: "S", lastName: "A", email: "sa2@example.com", adminRole: "SUPPORT_AGENT" },
  });
  const token = mockAuthAs({ sub: "support-agent-2", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/drivers/${driver.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "SUSPENDED" });

  assert.equal(res.status, 403);
});

test("PATCH /api/drivers/me updates the calling driver's own phone number", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-phone-1", role: "DRIVER", firstName: "P", lastName: "H", email: "ph1@example.com", phoneNumber: "0800000000" },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  const token = mockAuthAs({ sub: "drv-phone-1", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ phoneNumber: "0801234567" });
  assert.equal(res.status, 200);
  assert.equal(res.body.phoneNumber, "0801234567");

  const updated = await prisma.user.findUnique({ where: { id: user.id } });
  assert.equal(updated?.phoneNumber, "0801234567");
});

test("PATCH /api/drivers/me/preferences persists language and quiet mode, and a non-driver user is rejected", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-prefs-1", role: "DRIVER", firstName: "P", lastName: "F", email: "pf1@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, preferredLanguage: "English", quietModePreferred: false } });
  const token = mockAuthAs({ sub: "drv-prefs-1", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/preferences")
    .set("Authorization", `Bearer ${token}`)
    .send({ preferredLanguage: "Yoruba", quietModePreferred: true });
  assert.equal(res.status, 200);
  assert.equal(res.body.preferredLanguage, "Yoruba");
  assert.equal(res.body.quietModePreferred, true);

  const updated = await prisma.driver.findUnique({ where: { id: driver.id } });
  assert.equal(updated?.preferredLanguage, "Yoruba");
  assert.equal(updated?.quietModePreferred, true);

  // A caller with no driver profile at all.
  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "not-a-driver-yet", groups: ["Driver"] });
  const missing = await request(app)
    .patch("/api/drivers/me/preferences")
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ quietModePreferred: true });
  assert.equal(missing.status, 404);
});

test("PATCH /api/drivers/me/preferences rejects an empty body", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-prefs-empty", role: "DRIVER", firstName: "P", lastName: "E", email: "pfe@example.com" },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  const token = mockAuthAs({ sub: "drv-prefs-empty", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/preferences")
    .set("Authorization", `Bearer ${token}`)
    .send({});
  assert.equal(res.status, 400);
});

test("PATCH /api/drivers/me/availability lets an ACTIVE driver go online, blocks a pending one", async () => {
  // A pending driver cannot go online.
  const pendingUser = await prisma.user.create({
    data: { cognitoSub: "drv-pending", role: "DRIVER", firstName: "P", lastName: "D", email: "pd@example.com" },
  });
  await prisma.driver.create({ data: { userId: pendingUser.id, status: "PENDING_REVIEW" } });
  const pendingToken = mockAuthAs({ sub: "drv-pending", groups: ["Driver"] });
  const blocked = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${pendingToken}`)
    .send({ isOnline: true });
  assert.equal(blocked.status, 409);

  restoreAuth();

  // An approved (ACTIVE) driver can toggle online.
  const activeUser = await prisma.user.create({
    data: { cognitoSub: "drv-active", role: "DRIVER", firstName: "A", lastName: "D", email: "ad@example.com" },
  });
  await prisma.driver.create({ data: { userId: activeUser.id, status: "ACTIVE" } });
  const activeToken = mockAuthAs({ sub: "drv-active", groups: ["Driver"] });
  const ok = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${activeToken}`)
    .send({ isOnline: true });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.isOnline, true);
});

// A REQUESTED trip is only ever matched once, synchronously, at creation —
// there is no background retry (see services/matching.ts). Going online is
// the one moment that can change the outcome for a rider already waiting,
// so it must retry matching, not just flip isOnline and leave them stuck.
test("PATCH /api/drivers/me/availability retries matching for a rider already waiting", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-retry-1", role: "RIDER", firstName: "R", lastName: "W", email: "rw@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "REQUESTED" },
  });

  const driverUser = await prisma.user.create({
    data: { cognitoSub: "drv-retry-1", role: "DRIVER", firstName: "D", lastName: "R", email: "dr@example.com" },
  });
  await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const token = mockAuthAs({ sub: "drv-retry-1", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: true });
  assert.equal(res.status, 200);

  const updated = await prisma.trip.findUnique({ where: { id: trip.id } });
  // Offered, not yet matched — the driver still has to explicitly accept
  // (see services/matching.ts / POST /trips/:id/accept).
  assert.equal(updated?.status, "OFFERED");
  assert.ok(updated?.driverId);

  const driverNotifications = await prisma.notification.findMany({ where: { userId: driverUser.id } });
  assert.ok(driverNotifications.some((n) => n.type === "RIDE_OFFERED" && n.referenceId === trip.id));
  // The rider is not told "driver assigned" until the driver actually accepts.
  const riderNotifications = await prisma.notification.findMany({ where: { userId: rider.id } });
  assert.ok(!riderNotifications.some((n) => n.type === "RIDE_DRIVER_ASSIGNED"));
});

test("PATCH /api/drivers/me/availability does not reach back and match a stale, long-abandoned request", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-retry-2", role: "RIDER", firstName: "R", lastName: "S", email: "rs@example.com" },
  });
  const staleTrip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 12,
      status: "REQUESTED",
      requestedAt: new Date(Date.now() - 60 * 60_000), // an hour ago
    },
  });

  const driverUser = await prisma.user.create({
    data: { cognitoSub: "drv-retry-2", role: "DRIVER", firstName: "D", lastName: "S", email: "ds@example.com" },
  });
  await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const token = mockAuthAs({ sub: "drv-retry-2", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/drivers/me/availability")
    .set("Authorization", `Bearer ${token}`)
    .send({ isOnline: true });
  assert.equal(res.status, 200);

  const stillRequested = await prisma.trip.findUnique({ where: { id: staleTrip.id } });
  assert.equal(stillRequested?.status, "REQUESTED");
  assert.equal(stillRequested?.driverId, null);
});

test("POST /api/drivers/me/location records the driver's position in the realtime hub (backs the admin Live Map)", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-loc-1", role: "DRIVER", firstName: "L", lastName: "D", email: "ld@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", isOnline: true } });
  const token = mockAuthAs({ sub: "drv-loc-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/drivers/me/location")
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 6.5244, lng: 3.3792 });

  assert.equal(res.status, 200);
  assert.equal(res.body.driverId, driver.id);
  const stored = getLatestDriverLocation(driver.id);
  assert.equal(stored?.lat, 6.5244);
  assert.equal(stored?.lng, 3.3792);
});

test("GET /api/drivers/:driverId/documents/:documentId/url returns a signed URL for an Admin", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-1", role: "DRIVER", firstName: "D", lastName: "V", email: "dv1@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-1/license.pdf" },
  });

  const token = mockAuthAs({ sub: "admin-doc-1", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.ok(typeof res.body.url === "string" && res.body.url.startsWith("http"));
  assert.equal(res.body.expiresIn, 300);

  const audit = await prisma.auditLog.findFirst({ where: { entityId: doc.id, action: "DOCUMENT_VIEWED" } });
  assert.ok(audit, "expected a DOCUMENT_VIEWED audit entry");
});

test("GET /api/drivers/:driverId/documents/:documentId/url rejects a non-Admin caller", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-2", role: "DRIVER", firstName: "D", lastName: "V", email: "dv2@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-2/license.pdf" },
  });

  const token = mockAuthAs({ sub: "drv-doc-2", groups: ["Driver"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});

test("GET /api/drivers/:driverId/documents/:documentId/url rejects an admin whose role lacks drivers:write", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-3", role: "DRIVER", firstName: "D", lastName: "V", email: "dv3@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "drv-doc-3/license.pdf" },
  });
  await prisma.user.create({
    data: {
      cognitoSub: "finance-doc-url",
      role: "ADMIN",
      adminRole: "FINANCE_VIEWER",
      firstName: "F",
      lastName: "V",
      email: "fv-doc-url@example.com",
    },
  });

  const token = mockAuthAs({ sub: "finance-doc-url", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s for a driver that doesn't exist", async () => {
  const token = mockAuthAs({ sub: "admin-doc-2", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/does-not-exist/documents/also-missing/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s for a document that doesn't exist", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-4", role: "DRIVER", firstName: "D", lastName: "V", email: "dv4@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-doc-3", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/does-not-exist/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s when the document belongs to a different driver", async () => {
  const userA = await prisma.user.create({
    data: { cognitoSub: "drv-doc-5a", role: "DRIVER", firstName: "A", lastName: "V", email: "dv5a@example.com" },
  });
  const driverA = await prisma.driver.create({ data: { userId: userA.id } });
  const userB = await prisma.user.create({
    data: { cognitoSub: "drv-doc-5b", role: "DRIVER", firstName: "B", lastName: "V", email: "dv5b@example.com" },
  });
  const driverB = await prisma.driver.create({ data: { userId: userB.id } });
  const docB = await prisma.driverDocument.create({
    data: { driverId: driverB.id, title: "License", fileKey: "drv-doc-5b/license.pdf" },
  });

  const token = mockAuthAs({ sub: "admin-doc-4", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driverA.id}/documents/${docB.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:driverId/documents/:documentId/url 404s when the document has no fileKey uploaded yet", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-doc-6", role: "DRIVER", firstName: "D", lastName: "V", email: "dv6@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", status: "NOT_UPLOADED" },
  });

  const token = mockAuthAs({ sub: "admin-doc-5", groups: ["Admin"] });
  const res = await request(app)
    .get(`/api/drivers/${driver.id}/documents/${doc.id}/url`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

test("GET /api/drivers/:id includes the driver's phoneNumber (or null) for the admin detail view", async () => {
  const user = await prisma.user.create({
    data: {
      cognitoSub: "drv-phone-1",
      role: "DRIVER",
      firstName: "P",
      lastName: "H",
      email: "ph1@example.com",
      phoneNumber: "+2348012345678",
    },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });

  const token = mockAuthAs({ sub: "admin-doc-6", groups: ["Admin"] });
  const res = await request(app).get(`/api/drivers/${driver.id}`).set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.user.phoneNumber, "+2348012345678");
});

test("POST /api/drivers/me/location rejects an out-of-range coordinate", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "drv-loc-2", role: "DRIVER", firstName: "L", lastName: "D", email: "ld2@example.com" },
  });
  await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
  const token = mockAuthAs({ sub: "drv-loc-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/drivers/me/location")
    .set("Authorization", `Bearer ${token}`)
    .send({ lat: 999, lng: 3.3792 });

  assert.equal(res.status, 400);
});
