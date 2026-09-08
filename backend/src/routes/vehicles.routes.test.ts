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

test("GET /api/vehicles lets an admin see every driver's vehicles with owner info", async () => {
  const driverA = await createDriver("driver-sub-admin-1");
  const driverB = await createDriver("driver-sub-admin-2");
  await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Toyota", model: "Camry", colour: "Silver", plateNumber: "GGG-777", year: "2021" },
  });
  await prisma.vehicle.create({
    data: { driverId: driverB.id, brand: "Honda", model: "Accord", colour: "Black", plateNumber: "HHH-888", year: "2022" },
  });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app).get("/api/vehicles").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 2);
  const plates = res.body.data.map((v: { plateNumber: string }) => v.plateNumber).sort();
  assert.deepEqual(plates, ["GGG-777", "HHH-888"]);
  assert.ok(res.body.data[0].driver.user.email);
});

test("GET /api/vehicles rejects a non-admin caller", async () => {
  await createDriver("driver-sub-admin-3");
  const token = mockAuthAs({ sub: "driver-sub-admin-3", groups: ["Driver"] });

  const res = await request(app).get("/api/vehicles").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

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

test("POST /api/vehicles rejects a photoKey that doesn't belong to the caller", async () => {
  await createDriver("driver-sub-photo-1");
  const token = mockAuthAs({ sub: "driver-sub-photo-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Toyota",
      model: "Camry",
      colour: "Silver",
      plateNumber: "PHT-100",
      year: "2022",
      photoKey: "someone-elses-sub/photo.jpg",
    });

  assert.equal(res.status, 403);
});

test("POST /api/vehicles accepts a photoKey the caller owns and never returns the raw key", async () => {
  await createDriver("driver-sub-photo-2");
  const token = mockAuthAs({ sub: "driver-sub-photo-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Toyota",
      model: "Camry",
      colour: "Silver",
      plateNumber: "PHT-200",
      year: "2022",
      photoKey: "driver-sub-photo-2/photo.jpg",
    });

  assert.equal(res.status, 201);
  assert.ok(!("photoKey" in res.body), "raw S3 key must never be returned to the client");
  assert.ok("photoUrl" in res.body);
});

test("PATCH /api/vehicles/:id rejects a photoKey that doesn't belong to the caller", async () => {
  const driver = await createDriver("driver-sub-photo-3");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Blue", plateNumber: "PHT-300", year: "2020" },
  });
  const token = mockAuthAs({ sub: "driver-sub-photo-3", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ photoKey: "someone-elses-sub/photo.jpg" });

  assert.equal(res.status, 403);
  const unchanged = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.equal(unchanged?.photoKey, null);
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

test("DELETE /api/vehicles/:id removes a vehicle the calling driver owns", async () => {
  const driver = await createDriver("driver-sub-6");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Mazda", model: "3", colour: "Grey", plateNumber: "DDD-444", year: "2020" },
  });
  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });

  const res = await request(app).delete(`/api/vehicles/${vehicle.id}`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 204);

  const gone = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.equal(gone, null);
});

test("DELETE /api/vehicles/:id 404s when the vehicle belongs to a different driver", async () => {
  const driverA = await createDriver("driver-sub-7");
  await createDriver("driver-sub-8");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Kia", model: "Sportage", colour: "Blue", plateNumber: "EEE-555", year: "2021" },
  });

  const token = mockAuthAs({ sub: "driver-sub-8", groups: ["Driver"] });
  const res = await request(app).delete(`/api/vehicles/${vehicle.id}`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("DELETE /api/vehicles/:id rejects deleting a vehicle that's listed for rental", async () => {
  const driver = await createDriver("driver-sub-9");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Lexus", model: "RX", colour: "Black", plateNumber: "FFF-666", year: "2022", listedForRental: true },
  });
  await prisma.rentalListing.create({ data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 100, location: "Lagos" } });

  const token = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });
  const res = await request(app).delete(`/api/vehicles/${vehicle.id}`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 409);

  const stillThere = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.ok(stillThere);
});
