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

test("an active Rider can access a protected endpoint", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "rider-active-1",
      role: "RIDER",
      firstName: "A",
      lastName: "B",
      email: "rider-active-1@example.com",
      suspended: false,
    },
  });
  const token = mockAuthAs({ sub: "rider-active-1", groups: ["Rider"] });

  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});

test("a suspended Rider is rejected before reaching the route", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "rider-suspended-1",
      role: "RIDER",
      firstName: "A",
      lastName: "B",
      email: "rider-suspended-1@example.com",
      suspended: true,
    },
  });
  const token = mockAuthAs({ sub: "rider-suspended-1", groups: ["Rider"] });

  const res = await request(app).get("/api/riders/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
  assert.equal(res.body.error, "Account suspended");
});

test("a suspended Rider cannot request a trip either", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "rider-suspended-2",
      role: "RIDER",
      firstName: "A",
      lastName: "B",
      email: "rider-suspended-2@example.com",
      suspended: true,
    },
  });
  const token = mockAuthAs({ sub: "rider-suspended-2", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });
  assert.equal(res.status, 403);
});

test("an active Driver's protected-endpoint access is unchanged", async () => {
  const user = await prisma.user.create({
    data: {
      cognitoSub: "driver-active-1",
      role: "DRIVER",
      firstName: "D",
      lastName: "R",
      email: "driver-active-1@example.com",
      suspended: false,
    },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  const token = mockAuthAs({ sub: "driver-active-1", groups: ["Driver"] });

  const res = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});

test("a suspended Driver (User.suspended) is rejected, distinct from Driver.status", async () => {
  const user = await prisma.user.create({
    data: {
      cognitoSub: "driver-suspended-1",
      role: "DRIVER",
      firstName: "D",
      lastName: "R",
      email: "driver-suspended-1@example.com",
      suspended: true,
    },
  });
  // Driver.status is ACTIVE — User.suspended is the thing being enforced here.
  await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
  const token = mockAuthAs({ sub: "driver-suspended-1", groups: ["Driver"] });

  const res = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
  assert.equal(res.body.error, "Account suspended");
});

test("an Admin retains access even if their own User row is marked suspended (no admin lockout)", async () => {
  await prisma.user.create({
    data: {
      cognitoSub: "admin-suspended-1",
      role: "ADMIN",
      firstName: "Ad",
      lastName: "Min",
      email: "admin-suspended-1@example.com",
      suspended: true,
    },
  });
  const token = mockAuthAs({ sub: "admin-suspended-1", groups: ["Admin"] });

  const res = await request(app).get("/api/admin/dashboard").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});

test("an Admin can still un-suspend another user (recovery path stays open)", async () => {
  const suspendedUser = await prisma.user.create({
    data: {
      cognitoSub: "rider-to-recover",
      role: "RIDER",
      firstName: "R",
      lastName: "E",
      email: "rider-to-recover@example.com",
      suspended: true,
    },
  });
  const token = mockAuthAs({ sub: "admin-sub-recovery", groups: ["Admin"] });

  const res = await request(app)
    .patch(`/api/riders/${suspendedUser.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ suspended: false });

  assert.equal(res.status, 200);
  assert.equal(res.body.suspended, false);
});

test("a caller with a valid token but no User row yet is not blocked by the suspension check", async () => {
  // Simulates the first call right after Cognito sign-up, before
  // POST /riders/me has ever run — there's no User row (and thus no
  // suspended flag) to check yet.
  const token = mockAuthAs({ sub: "brand-new-rider", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${token}`)
    .send({ firstName: "New", lastName: "Rider", email: "brand-new-rider@example.com" });

  assert.equal(res.status, 201);
});
