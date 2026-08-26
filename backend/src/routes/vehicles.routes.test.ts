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

test("POST /api/vehicles accepts vin and vehicleType and starts PENDING verification", async () => {
  await createDriver("driver-sub-6");
  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${token}`)
    .send({
      brand: "Toyota",
      model: "Camry",
      colour: "Black",
      plateNumber: "VIN-001",
      year: "2022",
      vin: "1HGCM82633A123456",
      vehicleType: "LUXURY",
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.vin, "1HGCM82633A123456");
  assert.equal(res.body.vehicleType, "LUXURY");
  assert.equal(res.body.verificationStatus, "PENDING");
  assert.equal(res.body.isActive, true);
  assert.deepEqual(res.body.photos, []);
});

test("GET /api/vehicles/:id returns a driver's own vehicle with photos and documents, 404s for another driver's", async () => {
  const driverA = await createDriver("driver-sub-7");
  await createDriver("driver-sub-8");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Ford", model: "Fusion", colour: "Grey", plateNumber: "GET-001", year: "2020" },
  });
  await prisma.vehiclePhoto.create({ data: { vehicleId: vehicle.id, fileKey: "driver-sub-7/x.jpg", photoType: "FRONT" } });

  const ownerToken = mockAuthAs({ sub: "driver-sub-7", groups: ["Driver"] });
  const ownRes = await request(app).get(`/api/vehicles/${vehicle.id}`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownRes.status, 200);
  assert.equal(ownRes.body.photos.length, 1);
  assert.equal(ownRes.body.photos[0].photoType, "FRONT");

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "driver-sub-8", groups: ["Driver"] });
  const strangerRes = await request(app).get(`/api/vehicles/${vehicle.id}`).set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 404);
});

test("PATCH /api/vehicles/:id/deactivate soft-deactivates my own vehicle, 404s for another driver's", async () => {
  const driverA = await createDriver("driver-sub-9");
  await createDriver("driver-sub-10");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Kia", model: "Soul", colour: "Yellow", plateNumber: "DEACT-1", year: "2021" },
  });

  const strangerToken = mockAuthAs({ sub: "driver-sub-10", groups: ["Driver"] });
  const strangerRes = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/deactivate`)
    .set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 404);

  restoreAuth();
  const ownerToken = mockAuthAs({ sub: "driver-sub-9", groups: ["Driver"] });
  const ownRes = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/deactivate`)
    .set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownRes.status, 200);
  assert.equal(ownRes.body.isActive, false);

  const stillListed = await request(app).get("/api/vehicles/me").set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(stillListed.body.length, 1); // deactivated, not deleted — still visible
});

test("POST /api/vehicles/:id/resubmit only works from REJECTED, and clears the reason", async () => {
  const driver = await createDriver("driver-sub-11");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "VW", model: "Golf", colour: "Blue", plateNumber: "RESUB-1", year: "2019" },
  });
  const token = mockAuthAs({ sub: "driver-sub-11", groups: ["Driver"] });

  const tooEarly = await request(app).post(`/api/vehicles/${vehicle.id}/resubmit`).set("Authorization", `Bearer ${token}`);
  assert.equal(tooEarly.status, 409);

  await prisma.vehicle.update({
    where: { id: vehicle.id },
    data: { verificationStatus: "REJECTED", verificationReason: "Plate photo unreadable" },
  });

  const res = await request(app).post(`/api/vehicles/${vehicle.id}/resubmit`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.verificationStatus, "PENDING");
  assert.equal(res.body.verificationReason, null);
});

test("POST /api/vehicles/:id/photos registers a photo when the fileKey belongs to the caller, rejects otherwise", async () => {
  const driver = await createDriver("driver-sub-12");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Mazda", model: "3", colour: "Red", plateNumber: "PHOTO-1", year: "2020" },
  });
  const token = mockAuthAs({ sub: "driver-sub-12", groups: ["Driver"] });

  const forged = await request(app)
    .post(`/api/vehicles/${vehicle.id}/photos`)
    .set("Authorization", `Bearer ${token}`)
    .send({ fileKey: "someone-else-sub/stolen.jpg", photoType: "FRONT" });
  assert.equal(forged.status, 403);

  const ok = await request(app)
    .post(`/api/vehicles/${vehicle.id}/photos`)
    .set("Authorization", `Bearer ${token}`)
    .send({ fileKey: "driver-sub-12/front.jpg", photoType: "FRONT", displayOrder: 0 });
  assert.equal(ok.status, 201);
  assert.equal(ok.body.photoType, "FRONT");
  assert.ok("url" in ok.body);
});

test("POST /api/vehicles/:id/photos 404s for a vehicle owned by another driver, even with a valid own fileKey", async () => {
  const driverA = await createDriver("driver-sub-13");
  await createDriver("driver-sub-14");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Nissan", model: "Altima", colour: "White", plateNumber: "PHOTO-2", year: "2020" },
  });

  const strangerToken = mockAuthAs({ sub: "driver-sub-14", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/vehicles/${vehicle.id}/photos`)
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ fileKey: "driver-sub-14/legit-but-wrong-vehicle.jpg", photoType: "FRONT" });

  assert.equal(res.status, 404);
});

test("DELETE /api/vehicles/:id/photos/:photoId removes my own vehicle's photo, 404s for another driver's", async () => {
  const driverA = await createDriver("driver-sub-15");
  await createDriver("driver-sub-16");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Subaru", model: "Impreza", colour: "Blue", plateNumber: "PHOTO-3", year: "2020" },
  });
  const photo = await prisma.vehiclePhoto.create({ data: { vehicleId: vehicle.id, fileKey: "driver-sub-15/x.jpg" } });

  const strangerToken = mockAuthAs({ sub: "driver-sub-16", groups: ["Driver"] });
  const strangerRes = await request(app)
    .delete(`/api/vehicles/${vehicle.id}/photos/${photo.id}`)
    .set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 404);

  restoreAuth();
  const ownerToken = mockAuthAs({ sub: "driver-sub-15", groups: ["Driver"] });
  const ownRes = await request(app)
    .delete(`/api/vehicles/${vehicle.id}/photos/${photo.id}`)
    .set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownRes.status, 204);

  const remaining = await prisma.vehiclePhoto.findUnique({ where: { id: photo.id } });
  assert.equal(remaining, null);
});

test("PATCH /api/vehicles/:id/review rejects a non-Admin caller", async () => {
  const driver = await createDriver("driver-sub-17");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Chevy", model: "Malibu", colour: "Silver", plateNumber: "REVIEW-1", year: "2020" },
  });
  const token = mockAuthAs({ sub: "driver-sub-17", groups: ["Driver"] });

  const res = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });
  assert.equal(res.status, 403);
});

test("PATCH /api/vehicles/:id/review requires a reason to reject, and records the reviewing Admin", async () => {
  const driver = await createDriver("driver-sub-18");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Hyundai", model: "Sonata", colour: "Black", plateNumber: "REVIEW-2", year: "2020" },
  });
  const adminUser = await prisma.user.create({
    data: { cognitoSub: "admin-sub-2", role: "ADMIN", firstName: "A", lastName: "D", email: "admin2@example.com" },
  });
  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });

  const missingReason = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED" });
  assert.equal(missingReason.status, 400);

  const rejected = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED", reason: "VIN does not match registration" });
  assert.equal(rejected.status, 200);
  assert.equal(rejected.body.verificationStatus, "REJECTED");
  assert.equal(rejected.body.verificationReason, "VIN does not match registration");
  assert.equal(rejected.body.verifiedById, adminUser.id);
  assert.ok(rejected.body.verifiedAt);

  const approved = await request(app)
    .patch(`/api/vehicles/${vehicle.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });
  assert.equal(approved.status, 200);
  assert.equal(approved.body.verificationStatus, "APPROVED");
  assert.equal(approved.body.verificationReason, null);
});
