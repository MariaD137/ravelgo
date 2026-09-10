import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { env } from "../config/env";
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
      photoKeys: ["someone-elses-sub/photo.jpg"],
    });

  assert.equal(res.status, 403);
});

test("POST /api/vehicles accepts photoKeys the caller owns and never returns raw keys", async () => {
  const beforeCdn = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = "cdn.ravelgo.example.com";
  try {
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
        photoKeys: ["driver-sub-photo-2/photo-1.jpg", "driver-sub-photo-2/photo-2.jpg"],
      });

    assert.equal(res.status, 201);
    assert.ok(!("photoKeys" in res.body), "raw S3 keys must never be returned to the client");
    assert.ok(!("photoKey" in res.body), "raw S3 key must never be returned to the client");
    assert.equal(res.body.photoUrls.length, 2);
    assert.equal(res.body.photoUrl, res.body.photoUrls[0]);
  } finally {
    env.ASSETS_CDN_DOMAIN = beforeCdn;
  }
});

test("POST /api/vehicles rejects more than 7 photos", async () => {
  await createDriver("driver-sub-photo-many");
  const token = mockAuthAs({ sub: "driver-sub-photo-many", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Toyota",
      model: "Camry",
      colour: "Silver",
      plateNumber: "PHT-800",
      year: "2022",
      photoKeys: Array.from({ length: 8 }, (_, i) => `driver-sub-photo-many/photo-${i}.jpg`),
    });

  assert.equal(res.status, 400);
});

test("PATCH /api/vehicles/:id rejects an addPhotoKeys entry that doesn't belong to the caller", async () => {
  const driver = await createDriver("driver-sub-photo-3");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Blue", plateNumber: "PHT-300", year: "2020" },
  });
  const token = mockAuthAs({ sub: "driver-sub-photo-3", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ addPhotoKeys: ["someone-elses-sub/photo.jpg"] });

  assert.equal(res.status, 403);
  const unchanged = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.deepEqual(unchanged?.photoKeys, []);
});

test("PATCH /api/vehicles/:id can append and remove photos without ever receiving raw keys", async () => {
  const beforeCdn = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = "cdn.ravelgo.example.com";
  try {
    const driver = await createDriver("driver-sub-photo-4");
    const vehicle = await prisma.vehicle.create({
      data: {
        driverId: driver.id,
        brand: "Kia",
        model: "Rio",
        colour: "Blue",
        plateNumber: "PHT-400",
        year: "2020",
        photoKeys: ["driver-sub-photo-4/existing-1.jpg", "driver-sub-photo-4/existing-2.jpg"],
      },
    });
    const token = mockAuthAs({ sub: "driver-sub-photo-4", groups: ["Driver"] });

    const get = await request(app).get("/api/vehicles/me").set("Authorization", `Bearer ${token}`);
    const existingUrls: string[] = get.body[0].photoUrls;
    assert.equal(existingUrls.length, 2);

    const res = await request(app)
      .patch(`/api/vehicles/${vehicle.id}`)
      .set("Authorization", `Bearer ${token}`)
      .send({ removePhotoUrls: [existingUrls[0]], addPhotoKeys: ["driver-sub-photo-4/new-1.jpg"] });

    assert.equal(res.status, 200);
    assert.equal(res.body.photoUrls.length, 2);
    assert.ok(!res.body.photoUrls.includes(existingUrls[0]));
    assert.ok(res.body.photoUrls.includes(existingUrls[1]));
  } finally {
    env.ASSETS_CDN_DOMAIN = beforeCdn;
  }
});

test("PATCH /api/vehicles/:id rejects growing past 7 photos", async () => {
  const driver = await createDriver("driver-sub-photo-5");
  const vehicle = await prisma.vehicle.create({
    data: {
      driverId: driver.id,
      brand: "Kia",
      model: "Rio",
      colour: "Blue",
      plateNumber: "PHT-500",
      year: "2020",
      photoKeys: Array.from({ length: 6 }, (_, i) => `driver-sub-photo-5/existing-${i}.jpg`),
    },
  });
  const token = mockAuthAs({ sub: "driver-sub-photo-5", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ addPhotoKeys: ["driver-sub-photo-5/new-1.jpg", "driver-sub-photo-5/new-2.jpg"] });

  assert.equal(res.status, 400);
  const unchanged = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.equal(unchanged?.photoKeys.length, 6);
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
