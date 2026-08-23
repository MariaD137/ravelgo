// Concurrency coverage for the two Ride/Courier/Rental conflict pairs not
// already covered elsewhere: Ride<->Rental and Courier<->Rental, each
// racing to reserve the same driver via services/driver-availability.ts.
// The other pairs (Ride<->Ride, Ride<->Courier, Courier<->Courier,
// Rental<->Rental at both the date-overlap and driver-activation levels)
// already have Promise.all coverage in trips.routes.test.ts,
// courier.routes.test.ts, and rentals.routes.test.ts respectively.
import assert from "node:assert/strict";
import { after, afterEach, beforeEach, mock, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { verifier } from "../middleware/auth";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.surgeZone.deleteMany();
  await prisma.pricingRule.deleteMany();
  await resetDb();
  await prisma.$disconnect();
});

async function createDriverWithVehicle(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  // online: true — matching.ts only considers online drivers eligible, and
  // this file's whole point is racing a real ride-match against another
  // domain, so the driver must actually be matching-eligible.
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", online: true } });
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Tesla", model: "Model 3", colour: "White", plateNumber: `${cognitoSub}-1`, year: "2022" },
  });
  return { driver, vehicle };
}

async function createConfirmedBooking(driverCognitoSub: string) {
  const { driver, vehicle } = await createDriverWithVehicle(driverCognitoSub);
  const listing = await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 100, location: "Lagos", status: "APPROVED" },
  });
  const renterUser = await prisma.user.create({
    data: { cognitoSub: `renter-for-${driverCognitoSub}`, role: "RIDER", firstName: "R", lastName: "N", email: `renter-${driverCognitoSub}@example.com` },
  });
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renterUser.id,
      vehicleId: vehicle.id,
      startAt: new Date("2028-06-01T00:00:00.000Z"),
      endAt: new Date("2028-06-05T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 400,
    },
  });
  return { driver, vehicle, booking };
}

test("Concurrency (Ride<->Rental): one driver — matching a new ride and activating a rental booking race — exactly one wins", async () => {
  const { driver, booking } = await createConfirmedBooking("driver-sub-xd-ride-rental");
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-xd-ride-rental", role: "RIDER", firstName: "R", lastName: "X", email: "rx1@example.com" },
  });

  const riderToken = "mock.rider-sub-xd-ride-rental";
  const driverToken = "mock.driver-sub-xd-ride-rental";
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate === riderToken) return { sub: "rider-sub-xd-ride-rental", "cognito:groups": ["Rider"] } as never;
    if (candidate === driverToken) return { sub: "driver-sub-xd-ride-rental", "cognito:groups": ["Driver"] } as never;
    throw new Error("invalid token");
  });

  const [tripRes, activateRes] = await Promise.all([
    request(app)
      .post("/api/trips")
      .set("Authorization", `Bearer ${riderToken}`)
      .send({ pickup: "Home", destination: "Airport", estimatedFare: 20 }),
    request(app).patch(`/api/rentals/bookings/${booking.id}/activate`).set("Authorization", `Bearer ${driverToken}`),
  ]);

  assert.equal(tripRes.status, 201);
  assert.ok(activateRes.status === 200 || activateRes.status === 409);

  const finalTrip = await prisma.trip.findUnique({ where: { id: tripRes.body.id } });
  const finalBooking = await prisma.rentalBooking.findUnique({ where: { id: booking.id } });

  const rideWon = finalTrip?.driverId === driver.id;
  const rentalWon = finalBooking?.status === "ACTIVE";
  // The single driver can win at most one of the two competing assignments.
  assert.notEqual(rideWon, rentalWon);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1);
});

test("Concurrency (Courier<->Rental): one driver — accepting a courier request and activating a rental booking race — exactly one wins", async () => {
  const { driver, booking } = await createConfirmedBooking("driver-sub-xd-courier-rental");
  const sender = await prisma.user.create({
    data: { cognitoSub: "rider-sub-xd-courier-rental", role: "RIDER", firstName: "R", lastName: "X", email: "rx2@example.com" },
  });
  const courierReq = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "Box",
      recipientName: "X",
      recipientPhone: "555-1",
      estimatedFare: 10,
    },
  });

  const driverToken = mockAuthAs({ sub: "driver-sub-xd-courier-rental", groups: ["Driver"] });

  const [courierRes, activateRes] = await Promise.all([
    request(app).patch(`/api/courier-requests/${courierReq.id}/accept`).set("Authorization", `Bearer ${driverToken}`),
    request(app).patch(`/api/rentals/bookings/${booking.id}/activate`).set("Authorization", `Bearer ${driverToken}`),
  ]);

  const statuses = [courierRes.status, activateRes.status].sort();
  // One of the two must be a clean conflict (409); the other succeeds.
  assert.ok(statuses.includes(409));

  const finalCourier = await prisma.courierRequest.findUnique({ where: { id: courierReq.id } });
  const finalBooking = await prisma.rentalBooking.findUnique({ where: { id: booking.id } });

  const courierWon = finalCourier?.status === "MATCHED";
  const rentalWon = finalBooking?.status === "ACTIVE";
  assert.notEqual(courierWon, rentalWon);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1);
});
