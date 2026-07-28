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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id } });
}

test("POST /api/car-paddy submits a request for the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/car-paddy")
    .set("Authorization", `Bearer ${token}`)
    .send({ plateNumber: "XYZ-999" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "SUBMITTED");
});

test("GET /api/car-paddy rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/car-paddy").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /api/car-paddy/:id lets an Admin approve and stamps reviewedAt", async () => {
  const driver = await createDriver("driver-sub-3");
  const req = await prisma.carPaddyRequest.create({ data: { driverId: driver.id, plateNumber: "AAA-1" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/car-paddy/${req.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");
  assert.ok(res.body.reviewedAt);
});
