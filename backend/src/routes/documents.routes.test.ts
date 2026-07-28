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

test("POST /api/documents registers a document as PENDING for the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    .send({ title: "Driver's license", fileKey: "driver-sub-1/abc-license.pdf" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING");
});

test("GET /api/documents/me only returns the calling driver's own documents", async () => {
  const driverA = await createDriver("driver-sub-2");
  const driverB = await createDriver("driver-sub-3");
  await prisma.driverDocument.create({ data: { driverId: driverA.id, title: "Mine", fileKey: "k1" } });
  await prisma.driverDocument.create({ data: { driverId: driverB.id, title: "Not mine", fileKey: "k2" } });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].title, "Mine");
});

test("PATCH /api/documents/:id/review rejects a non-Admin caller", async () => {
  const driver = await createDriver("driver-sub-4");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k3" } });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});

test("PATCH /api/documents/:id/review lets an Admin approve a document", async () => {
  const driver = await createDriver("driver-sub-5");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k4" } });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");
});
