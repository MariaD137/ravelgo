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

async function createDriverWithVehicle(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } });
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Tesla", model: "Model 3", colour: "White", plateNumber: `${cognitoSub}-1`, year: "2022" },
  });
  return { driver, vehicle };
}

test("POST /api/rentals lists the driver's own vehicle and marks it listedForRental", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 99.5, location: "Lagos" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_APPROVAL");

  const updated = await prisma.vehicle.findUnique({ where: { id: vehicle.id } });
  assert.equal(updated?.listedForRental, true);
});

test("POST /api/rentals 404s when the vehicle belongs to someone else", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-2");
  await createDriverWithVehicle("driver-sub-3");
  const token = mockAuthAs({ sub: "driver-sub-3", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 50, location: "Abuja" });

  assert.equal(res.status, 404);
});

test("GET /api/rentals only shows approved listings to non-admin callers", async () => {
  const { driver, vehicle } = await createDriverWithVehicle("driver-sub-4");
  await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 40, location: "Kano", status: "PENDING_APPROVAL" },
  });
  const { driver: driver2, vehicle: vehicle2 } = await createDriverWithVehicle("driver-sub-5");
  await prisma.rentalListing.create({
    data: { driverId: driver2.id, vehicleId: vehicle2.id, dailyRate: 60, location: "Ibadan", status: "APPROVED" },
  });

  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });
  const res = await request(app).get("/api/rentals").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].status, "APPROVED");
});

test("PATCH /api/rentals/:id/status rejects a non-Admin caller", async () => {
  const { driver, vehicle } = await createDriverWithVehicle("driver-sub-6");
  const listing = await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 40, location: "Enugu" },
  });

  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/${listing.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});
