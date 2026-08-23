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

// Vehicle image (Part 1-3 of the vehicle-image feature): imageKey is an S3
// object key namespaced under the caller's own sub (exactly what
// POST /uploads/presign always mints), resolved server-side into
// Vehicle.imageUrl. ASSETS_PUBLIC_BASE_URL is unset in this test
// environment, so resolveAssetUrl's fallback applies and imageUrl equals
// the imageKey verbatim — see services/assets.test.ts for the CDN-configured
// resolution behaviour itself.
test("POST /api/vehicles accepts an own imageKey and resolves it into imageUrl", async () => {
  await createDriver("driver-sub-image-1");
  const token = mockAuthAs({ sub: "driver-sub-image-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Mercedes-Benz",
      model: "E-Class",
      colour: "Black",
      plateNumber: "IMG-001",
      year: "2023",
      imageKey: "driver-sub-image-1/photo.jpg",
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.imageUrl, "driver-sub-image-1/photo.jpg");
});

test("POST /api/vehicles rejects an imageKey namespaced under a different user", async () => {
  await createDriver("driver-sub-image-2");
  const token = mockAuthAs({ sub: "driver-sub-image-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Toyota",
      model: "Corolla",
      colour: "Blue",
      plateNumber: "IMG-002",
      year: "2020",
      imageKey: "someone-elses-sub/photo.jpg",
    });

  assert.equal(res.status, 403);
  const created = await prisma.vehicle.findUnique({ where: { plateNumber: "IMG-002" } });
  assert.equal(created, null);
});

test("POST /api/vehicles without imageKey leaves imageUrl null", async () => {
  await createDriver("driver-sub-image-3");
  const token = mockAuthAs({ sub: "driver-sub-image-3", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({ brand: "Honda", model: "Accord", colour: "Silver", plateNumber: "IMG-003", year: "2020" });

  assert.equal(res.status, 201);
  assert.equal(res.body.imageUrl, null);
});

test("PATCH /api/vehicles/:id accepts an own imageKey and updates imageUrl", async () => {
  const driver = await createDriver("driver-sub-image-4");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Black", plateNumber: "IMG-004", year: "2021" },
  });
  const token = mockAuthAs({ sub: "driver-sub-image-4", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ imageKey: "driver-sub-image-4/new-photo.jpg" });

  assert.equal(res.status, 200);
  assert.equal(res.body.imageUrl, "driver-sub-image-4/new-photo.jpg");
});

test("PATCH /api/vehicles/:id rejects an imageKey namespaced under a different user and leaves the vehicle unchanged", async () => {
  const driver = await createDriver("driver-sub-image-5");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Black", plateNumber: "IMG-005", year: "2021" },
  });
  const token = mockAuthAs({ sub: "driver-sub-image-5", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ imageKey: "someone-elses-sub/new-photo.jpg" });

  assert.equal(res.status, 403);
  const unchanged = await prisma.vehicle.findUniqueOrThrow({ where: { id: vehicle.id } });
  assert.equal(unchanged.imageUrl, null);
});

test("GET /api/vehicles/me reflects a previously-set imageUrl", async () => {
  const driver = await createDriver("driver-sub-image-6");
  await prisma.vehicle.create({
    data: {
      driverId: driver.id,
      brand: "BMW",
      model: "7 Series",
      colour: "Grey",
      plateNumber: "IMG-006",
      year: "2024",
      imageUrl: "driver-sub-image-6/existing-photo.jpg",
    },
  });
  const token = mockAuthAs({ sub: "driver-sub-image-6", groups: ["Driver"] });

  const res = await request(app).get("/api/vehicles/me").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body[0].imageUrl, "driver-sub-image-6/existing-photo.jpg");
});

test("PATCH /api/vehicles/:id 404s for another driver's vehicle even with a validly-owned imageKey", async () => {
  const driverA = await createDriver("driver-sub-image-7");
  await createDriver("driver-sub-image-8");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Ford", model: "Focus", colour: "White", plateNumber: "IMG-007", year: "2018" },
  });

  const token = mockAuthAs({ sub: "driver-sub-image-8", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ imageKey: "driver-sub-image-8/photo.jpg" });

  assert.equal(res.status, 404);
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
