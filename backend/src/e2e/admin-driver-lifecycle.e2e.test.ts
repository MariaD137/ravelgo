/**
 * A real end-to-end walkthrough of the admin_app driver-management flow
 * this session wired up (driver_list_screen.dart / driver_detail_screen.dart),
 * exercised at the HTTP/route layer against the real local Postgres
 * instance — the same database the Flutter app itself would hit through
 * ApiClient. The only thing stubbed is Cognito JWT *signature verification*
 * (mockAuthAs, per src/test/helpers.ts) — there is no real Cognito user
 * pool available locally; every route, authorization check, Prisma query,
 * and database write below is the genuine production code path.
 *
 * This directly proves the chain the task requires:
 *   HTTP PATCH -> requireAuth/requireRole -> Prisma -> Postgres -> response
 * and independently re-reads the row via a *separate* prisma.driver
 * query afterward, so a route that only updated its in-memory response
 * without actually persisting would be caught.
 */
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

test("admin driver lifecycle: suspend persists, survives a re-fetch, and unsuspend reverses it", async () => {
  // Real driver bootstrap, same as the driver_app onboarding flow.
  const driverToken = mockAuthAs({ sub: "e2e-driver-1", groups: ["Driver"] });
  const created = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Amaka", lastName: "Okafor", email: "amaka.e2e@example.com" });
  assert.equal(created.status, 201);
  const driverId = created.body.id as string;
  assert.equal(created.body.status, "PENDING_REVIEW");

  const adminToken = mockAuthAs({ sub: "e2e-admin-1", groups: ["Admin"] });

  // Admin dashboard's driver list would show PENDING_REVIEW here.
  const listBefore = await request(app).get("/api/drivers").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(listBefore.status, 200);
  assert.ok(listBefore.body.data.some((d: { id: string; status: string }) => d.id === driverId && d.status === "PENDING_REVIEW"));

  // Admin activates the driver — the real mutation behind driver_detail_screen.dart's "Approve" action.
  const activate = await request(app)
    .patch(`/api/drivers/${driverId}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(activate.status, 200);
  assert.equal(activate.body.status, "ACTIVE");

  const afterActivate = await prisma.driver.findUniqueOrThrow({ where: { id: driverId } });
  assert.equal(afterActivate.status, "ACTIVE");

  // Admin suspends the driver — the real mutation behind the "Suspend" action.
  const suspend = await request(app)
    .patch(`/api/drivers/${driverId}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "SUSPENDED" });
  assert.equal(suspend.status, 200);
  assert.equal(suspend.body.status, "SUSPENDED");

  // Independent re-read (simulates the app being closed and reopened /
  // pull-to-refresh) proves the suspension actually persisted in Postgres,
  // not just in the PATCH response body.
  const afterSuspend = await prisma.driver.findUniqueOrThrow({ where: { id: driverId } });
  assert.equal(afterSuspend.status, "SUSPENDED");

  const listAfterSuspend = await request(app).get("/api/drivers").set("Authorization", `Bearer ${adminToken}`);
  assert.ok(
    listAfterSuspend.body.data.some((d: { id: string; status: string }) => d.id === driverId && d.status === "SUSPENDED"),
  );

  // Admin unsuspends — the "Reactivate" action.
  const unsuspend = await request(app)
    .patch(`/api/drivers/${driverId}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "ACTIVE" });
  assert.equal(unsuspend.status, 200);
  assert.equal(unsuspend.body.status, "ACTIVE");

  const afterUnsuspend = await prisma.driver.findUniqueOrThrow({ where: { id: driverId } });
  assert.equal(afterUnsuspend.status, "ACTIVE");
});

test("admin driver lifecycle: a non-Admin caller cannot suspend a driver (authorization is enforced server-side)", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-driver-2", groups: ["Driver"] });
  const created = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Bayo", lastName: "Adeyemi", email: "bayo.e2e@example.com" });
  const driverId = created.body.id as string;

  // The same driver tries to suspend themself directly via the API —
  // proves the ownership/role check is a real backend gate, not just a
  // hidden button in the admin UI.
  const attempt = await request(app)
    .patch(`/api/drivers/${driverId}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "SUSPENDED" });
  assert.equal(attempt.status, 403);

  const unchanged = await prisma.driver.findUniqueOrThrow({ where: { id: driverId } });
  assert.equal(unchanged.status, "PENDING_REVIEW");
});

test("admin rider lifecycle (second administrative mutation): suspend blocks the rider's own subsequent requests", async () => {
  const riderToken = mockAuthAs({ sub: "e2e-rider-1", groups: ["Rider"] });
  const riderProfile = await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Chidi", lastName: "Eze", email: "chidi.e2e@example.com" });
  const riderId = riderProfile.body.id as string;

  const adminToken = mockAuthAs({ sub: "e2e-admin-2", groups: ["Admin"] });
  const suspend = await request(app)
    .patch(`/api/riders/${riderId}/status`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ suspended: true });
  assert.equal(suspend.status, 200);
  assert.equal(suspend.body.suspended, true);

  const persisted = await prisma.user.findUniqueOrThrow({ where: { id: riderId } });
  assert.equal(persisted.suspended, true);

  // requireAuth's own suspension check (auth.ts) blocks the suspended
  // rider's very next request across the whole API, not just one route.
  // mockAuthAs replaces the verifier's mock wholesale (see trips.routes.test.ts's
  // own owner/stranger pattern), so the rider's identity must be re-mocked
  // here — the token string is deterministic (`mock.<sub>`) and identical
  // to the one captured above, this just makes it valid again.
  const riderTokenAgain = mockAuthAs({ sub: "e2e-rider-1", groups: ["Rider"] });
  assert.equal(riderTokenAgain, riderToken);
  const blocked = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${riderTokenAgain}`);
  assert.equal(blocked.status, 403);
});
