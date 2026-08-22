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

test("POST /api/vehicles adds a vehicle owned by the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({ brand: "Toyota", model: "Corolla", colour: "Blue", plateNumber: "ABC-123", year: "2020" });

  assert.equal(res.status, 201);
  assert.equal(res.body.plateNumber, "ABC-123");
});

test("GET /api/vehicles/me only returns the calling driver's own vehicles", async () => {
  const driverA = await createDriver("driver-sub-2");
  const driverB = await createDriver("driver-sub-3");
  await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Honda", model: "Civic", colour: "Red", plateNumber: "AAA-111", year: "2019" },
  });
  await prisma.vehicle.create({
    data: { driverId: driverB.id, brand: "Kia", model: "Rio", colour: "Black", plateNumber: "BBB-222", year: "2021" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/vehicles/me").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].plateNumber, "AAA-111");
});

test("PATCH /api/vehicles/:id 404s when the vehicle belongs to a different driver", async () => {
  const driverA = await createDriver("driver-sub-4");
  await createDriver("driver-sub-5");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Ford", model: "Focus", colour: "White", plateNumber: "CCC-333", year: "2018" },
  });

  const token = mockAuthAs({ sub: "driver-sub-5", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ colour: "Green" });

  assert.equal(res.status, 404);
});

// Regression: neither POST nor PATCH used to unset isPrimary on a driver's
// other vehicles when marking a new one primary — matching.ts picks a
// vehicle via `orderBy: { isPrimary: "desc" }`, which only means anything
// if at most one vehicle can be primary at a time.
test("POST /api/vehicles unsets isPrimary on the driver's other vehicles when the new one is primary", async () => {
  const driver = await createDriver("driver-sub-primary-1");
  const first = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Honda", model: "Civic", colour: "Red", plateNumber: "P1", year: "2019", isPrimary: true },
  });

  const token = mockAuthAs({ sub: "driver-sub-primary-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({ brand: "Kia", model: "Rio", colour: "Black", plateNumber: "P2", year: "2021", isPrimary: true });

  assert.equal(res.status, 201);
  assert.equal(res.body.isPrimary, true);

  const stillPrimary = await prisma.vehicle.findMany({ where: { driverId: driver.id, isPrimary: true } });
  assert.equal(stillPrimary.length, 1);
  assert.equal(stillPrimary[0].id, res.body.id);

  const updatedFirst = await prisma.vehicle.findUniqueOrThrow({ where: { id: first.id } });
  assert.equal(updatedFirst.isPrimary, false);
});

test("PATCH /api/vehicles/:id unsets isPrimary on the driver's other vehicles when this one becomes primary", async () => {
  const driver = await createDriver("driver-sub-primary-2");
  const first = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Honda", model: "Civic", colour: "Red", plateNumber: "P3", year: "2019", isPrimary: true },
  });
  const second = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Black", plateNumber: "P4", year: "2021", isPrimary: false },
  });

  const token = mockAuthAs({ sub: "driver-sub-primary-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/vehicles/${second.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ isPrimary: true });

  assert.equal(res.status, 200);

  const stillPrimary = await prisma.vehicle.findMany({ where: { driverId: driver.id, isPrimary: true } });
  assert.equal(stillPrimary.length, 1);
  assert.equal(stillPrimary[0].id, second.id);

  const updatedFirst = await prisma.vehicle.findUniqueOrThrow({ where: { id: first.id } });
  assert.equal(updatedFirst.isPrimary, false);
});
