import assert from "node:assert/strict";
import { after, afterEach, beforeEach, mock, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { verifier } from "../middleware/auth";
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
  // ACTIVE — an admin-approved driver, since most of this file's tests are
  // about rental business logic, not the approval gate itself (see the
  // dedicated "pending/suspended driver" tests below for that).
  const driver = await prisma.driver.create({ data: { userId: user.id, status: "ACTIVE" } });
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
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].status, "APPROVED");
});

async function createRider(cognitoSub: string) {
  return prisma.user.create({
    data: { cognitoSub, role: "RIDER", firstName: "R", lastName: "I", email: `${cognitoSub}@example.com` },
  });
}

async function createApprovedListing(cognitoSub: string, dailyRate = 100) {
  const { driver, vehicle } = await createDriverWithVehicle(cognitoSub);
  const listing = await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate, location: "Lagos", status: "APPROVED" },
  });
  return { driver, vehicle, listing };
}

test("POST /api/rentals/:id/bookings creates a booking priced from the listing's dailyRate", async () => {
  const { listing } = await createApprovedListing("driver-sub-book-1", 100);
  await createRider("rider-sub-book-1");
  const token = mockAuthAs({ sub: "rider-sub-book-1", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/bookings`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startAt: "2027-01-01T00:00:00.000Z", endAt: "2027-01-03T00:00:00.000Z" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
  assert.equal(res.body.price, 200);
});

test("POST /api/rentals/:id/bookings rejects overlapping dates against a CONFIRMED booking (Rental->Rental)", async () => {
  const { listing, vehicle } = await createApprovedListing("driver-sub-book-2", 100);
  const renter1 = await createRider("rider-sub-book-2a");
  await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter1.id,
      vehicleId: vehicle.id,
      startAt: new Date("2027-02-05T00:00:00.000Z"),
      endAt: new Date("2027-02-10T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 500,
    },
  });
  await createRider("rider-sub-book-2b");
  const token = mockAuthAs({ sub: "rider-sub-book-2b", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/bookings`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startAt: "2027-02-07T00:00:00.000Z", endAt: "2027-02-12T00:00:00.000Z" });

  assert.equal(res.status, 409);
  assert.equal(res.body.code, "RENTAL_OVERLAP");
});

test("POST /api/rentals/:id/bookings does not block against a REQUESTED (unconfirmed) booking", async () => {
  const { listing, vehicle } = await createApprovedListing("driver-sub-book-3", 100);
  const renter1 = await createRider("rider-sub-book-3a");
  await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter1.id,
      vehicleId: vehicle.id,
      startAt: new Date("2027-03-05T00:00:00.000Z"),
      endAt: new Date("2027-03-10T00:00:00.000Z"),
      status: "REQUESTED",
      price: 500,
    },
  });
  await createRider("rider-sub-book-3b");
  const token = mockAuthAs({ sub: "rider-sub-book-3b", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/bookings`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startAt: "2027-03-07T00:00:00.000Z", endAt: "2027-03-09T00:00:00.000Z" });

  assert.equal(res.status, 201);
});

test("Concurrency: two renters booking overlapping dates for the same vehicle — exactly one wins", async () => {
  const { listing } = await createApprovedListing("driver-sub-book-race", 100);

  const tokenA = "mock.rider-sub-book-race-a";
  const tokenB = "mock.rider-sub-book-race-b";
  await createRider("rider-sub-book-race-a");
  await createRider("rider-sub-book-race-b");
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate === tokenA) return { sub: "rider-sub-book-race-a", "cognito:groups": ["Rider"] } as never;
    if (candidate === tokenB) return { sub: "rider-sub-book-race-b", "cognito:groups": ["Rider"] } as never;
    throw new Error("invalid token");
  });

  const body = { startAt: "2027-04-01T00:00:00.000Z", endAt: "2027-04-05T00:00:00.000Z" };
  const [resA, resB] = await Promise.all([
    request(app).post(`/api/rentals/${listing.id}/bookings`).set("Authorization", `Bearer ${tokenA}`).send(body),
    request(app).post(`/api/rentals/${listing.id}/bookings`).set("Authorization", `Bearer ${tokenB}`).send(body),
  ]);

  // Both REQUESTED bookings are logically allowed to coexist (REQUESTED
  // doesn't block — see OVERLAP_BLOCKING_STATUSES), so a 201/201 outcome is
  // the common case. But because the overlap check and the insert run
  // inside a SERIALIZABLE transaction (Part 12: never check-then-create
  // outside a transaction), Postgres's serializable snapshot isolation can
  // still abort one of two transactions that scanned the same predicate
  // range (same vehicleId) and then both inserted into it — a standard SSI
  // "dangerous structure," not a bug. Either outcome is therefore
  // acceptable here: what must never happen is silent data loss (both
  // succeeding with one overwriting the other) or the created booking being
  // for the wrong vehicle/renter.
  const statuses = [resA.status, resB.status];
  assert.ok(
    statuses.every((s) => s === 201 || s === 409),
    `expected only 201/409, got ${statuses.join(",")}`,
  );
  assert.ok(statuses.includes(201), "at least one concurrent booking attempt must succeed");
  if (resA.status === 201 && resB.status === 201) {
    assert.notEqual(resA.body.id, resB.body.id);
  }
});

test("Concurrency: confirming both overlapping REQUESTED bookings then activating both — only one activation can hold the vehicle at a time via driver reservation", async () => {
  const { driver, listing } = await createApprovedListing("driver-sub-book-race2", 100);
  const renter1 = await createRider("rider-sub-book-race2a");
  const renter2 = await createRider("rider-sub-book-race2b");
  const bookingA = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter1.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-05-01T00:00:00.000Z"),
      endAt: new Date("2027-05-05T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 400,
    },
  });
  const bookingB = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter2.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-06-01T00:00:00.000Z"),
      endAt: new Date("2027-06-05T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 400,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-book-race2", groups: ["Driver"] });
  const [resA, resB] = await Promise.all([
    request(app).patch(`/api/rentals/bookings/${bookingA.id}/activate`).set("Authorization", `Bearer ${token}`),
    request(app).patch(`/api/rentals/bookings/${bookingB.id}/activate`).set("Authorization", `Bearer ${token}`),
  ]);

  // The single driver behind this listing can only be operationally
  // occupied by one active rental at a time, even though the two bookings'
  // date ranges themselves don't overlap.
  const statuses = [resA.status, resB.status].sort();
  assert.deepEqual(statuses, [200, 409]);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1);
});

test("PATCH /api/rentals/bookings/:id/activate rejects when the driver is already MATCHED on a ride (Ride->Rental)", async () => {
  const { driver, listing } = await createApprovedListing("driver-sub-book-4", 100);
  const renter = await createRider("rider-sub-book-4");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-07-01T00:00:00.000Z"),
      endAt: new Date("2027-07-05T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 400,
    },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RIDE", assignmentId: "some-trip-id" },
  });

  const token = mockAuthAs({ sub: "driver-sub-book-4", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/activate`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
  assert.equal(res.body.code, "DRIVER_BUSY");
  assert.equal(res.body.activeAssignmentType, "RIDE");

  const finalBooking = await prisma.rentalBooking.findUnique({ where: { id: booking.id } });
  assert.equal(finalBooking?.status, "CONFIRMED");
});

test("POST /api/rentals rejects a driver who isn't ACTIVE (pending approval or suspended)", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-pending-rental", role: "DRIVER", firstName: "P", lastName: "D", email: "pdr@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id } }); // default PENDING_REVIEW
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Kia", model: "Rio", colour: "Blue", plateNumber: "PDR-1", year: "2020" },
  });

  const token = mockAuthAs({ sub: "driver-sub-pending-rental", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 50, location: "Lagos" });

  assert.equal(res.status, 403);
  const listings = await prisma.rentalListing.findMany({ where: { driverId: driver.id } });
  assert.equal(listings.length, 0);
});

test("PATCH /api/rentals/bookings/:id/decision rejects CONFIRMING as a suspended driver, but REJECTING still works", async () => {
  const { driver, listing } = await createApprovedListing("driver-sub-suspended-decision", 100);
  await prisma.driver.update({ where: { id: driver.id }, data: { status: "SUSPENDED" } });
  const renter = await createRider("rider-sub-suspended-decision");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-08-01T00:00:00.000Z"),
      endAt: new Date("2027-08-03T00:00:00.000Z"),
      status: "REQUESTED",
      price: 200,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-suspended-decision", groups: ["Driver"] });
  const confirm = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/decision`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "CONFIRMED" });
  assert.equal(confirm.status, 403, "a suspended driver must not be able to confirm new work");

  const reject = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/decision`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED" });
  assert.equal(reject.status, 200, "declining is always allowed, even while suspended");
});

test("PATCH /api/rentals/bookings/:id/activate rejects a suspended driver", async () => {
  const { driver, listing } = await createApprovedListing("driver-sub-suspended-activate", 100);
  const renter = await createRider("rider-sub-suspended-activate");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-09-01T00:00:00.000Z"),
      endAt: new Date("2027-09-03T00:00:00.000Z"),
      status: "CONFIRMED",
      price: 200,
    },
  });
  await prisma.driver.update({ where: { id: driver.id }, data: { status: "SUSPENDED" } });

  const token = mockAuthAs({ sub: "driver-sub-suspended-activate", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/activate`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 403);
  const finalBooking = await prisma.rentalBooking.findUnique({ where: { id: booking.id } });
  assert.equal(finalBooking?.status, "CONFIRMED", "must not be activated by a suspended driver");
});

test("PATCH /api/rentals/bookings/:id/end releases the driver's RENTAL assignment on COMPLETED", async () => {
  const { driver, listing } = await createApprovedListing("driver-sub-book-5", 100);
  const renter = await createRider("rider-sub-book-5");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-08-01T00:00:00.000Z"),
      endAt: new Date("2027-08-05T00:00:00.000Z"),
      status: "ACTIVE",
      price: 400,
    },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RENTAL", assignmentId: booking.id, vehicleId: listing.vehicleId },
  });

  const token = mockAuthAs({ sub: "driver-sub-book-5", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/end`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED" });

  assert.equal(res.status, 200);
  const assignment = await prisma.driverAssignment.findFirst({ where: { driverId: driver.id } });
  assert.equal(assignment?.status, "ENDED");
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

test("PATCH /api/rentals/bookings/:id/end rejects marking a REQUESTED booking COMPLETED (must go through CONFIRMED/ACTIVE)", async () => {
  const { listing } = await createApprovedListing("driver-sub-illegal-1", 100);
  const renter = await createRider("rider-sub-illegal-1");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2028-01-01T00:00:00.000Z"),
      endAt: new Date("2028-01-05T00:00:00.000Z"),
      status: "REQUESTED",
      price: 400,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-illegal-1", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/end`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED" });

  assert.equal(res.status, 409);
  const unchanged = await prisma.rentalBooking.findUnique({ where: { id: booking.id } });
  assert.equal(unchanged?.status, "REQUESTED");
});

test("PATCH /api/rentals/bookings/:id/end rejects ending an already-COMPLETED booking again", async () => {
  const { listing } = await createApprovedListing("driver-sub-illegal-2", 100);
  const renter = await createRider("rider-sub-illegal-2");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2028-02-01T00:00:00.000Z"),
      endAt: new Date("2028-02-05T00:00:00.000Z"),
      status: "COMPLETED",
      price: 400,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-illegal-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/end`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED" });

  assert.equal(res.status, 409);
});

test("PATCH /api/rentals/bookings/:id/activate rejects activating a REQUESTED (not yet CONFIRMED) booking", async () => {
  const { listing } = await createApprovedListing("driver-sub-illegal-3", 100);
  const renter = await createRider("rider-sub-illegal-3");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2028-03-01T00:00:00.000Z"),
      endAt: new Date("2028-03-05T00:00:00.000Z"),
      status: "REQUESTED",
      price: 400,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-illegal-3", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/activate`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);
});

test("RentalBooking.paymentStatus defaults to NOT_CONFIGURED (explicit non-payment state, Stripe not yet integrated)", async () => {
  const { listing } = await createApprovedListing("driver-sub-payment-1", 100);
  await createRider("rider-sub-payment-1");
  const token = mockAuthAs({ sub: "rider-sub-payment-1", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/bookings`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startAt: "2028-04-01T00:00:00.000Z", endAt: "2028-04-03T00:00:00.000Z" });

  assert.equal(res.status, 201);
  assert.equal(res.body.paymentStatus, "NOT_CONFIGURED");
});

test("POST /api/rentals/:id/bookings 404s cleanly on a malformed/garbage listing id (not a 500)", async () => {
  await createRider("rider-sub-malformed-1");
  const token = mockAuthAs({ sub: "rider-sub-malformed-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/rentals/' OR 1=1 --/bookings")
    .set("Authorization", `Bearer ${token}`)
    .send({ startAt: "2028-01-01T00:00:00.000Z", endAt: "2028-01-03T00:00:00.000Z" });

  assert.equal(res.status, 404);
});

test("PATCH /api/rentals/bookings/:id/activate 404s cleanly on a malformed/garbage booking id (not a 500)", async () => {
  const user = await prisma.user.create({
    data: { cognitoSub: "driver-sub-malformed-2", role: "DRIVER", firstName: "D", lastName: "R", email: "malformed2@example.com" },
  });
  await prisma.driver.create({ data: { userId: user.id } });
  const token = mockAuthAs({ sub: "driver-sub-malformed-2", groups: ["Driver"] });

  const res = await request(app)
    .patch("/api/rentals/bookings/' OR 1=1 --/activate")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 404);
});

// Regression: decideBooking() used to confirm a REQUESTED booking with no
// re-check against other bookings for the same vehicle/dates. Since
// REQUESTED bookings are deliberately allowed to overlap each other (see
// createBooking's own doc comment), two renters could both get a REQUESTED
// booking for the same overlapping dates, and the driver confirming both
// (one after another, no concurrency needed to hit this) used to produce
// two CONFIRMED bookings for the same vehicle on the same dates — the exact
// double-booking this table's overlap protection exists to prevent.
test("PATCH /api/rentals/bookings/:id/decision rejects confirming a REQUESTED booking that overlaps an already-CONFIRMED one", async () => {
  const { listing } = await createApprovedListing("driver-sub-decide-overlap", 100);
  const renter1 = await createRider("rider-sub-decide-overlap-a");
  const renter2 = await createRider("rider-sub-decide-overlap-b");

  const bookingA = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter1.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-07-01T00:00:00.000Z"),
      endAt: new Date("2027-07-05T00:00:00.000Z"),
      status: "REQUESTED",
      price: 400,
    },
  });
  const bookingB = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter2.id,
      vehicleId: listing.vehicleId,
      // Overlaps bookingA's date range.
      startAt: new Date("2027-07-03T00:00:00.000Z"),
      endAt: new Date("2027-07-08T00:00:00.000Z"),
      status: "REQUESTED",
      price: 400,
    },
  });

  const token = mockAuthAs({ sub: "driver-sub-decide-overlap", groups: ["Driver"] });

  const confirmA = await request(app)
    .patch(`/api/rentals/bookings/${bookingA.id}/decision`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "CONFIRMED" });
  assert.equal(confirmA.status, 200);
  assert.equal(confirmA.body.status, "CONFIRMED");

  const confirmB = await request(app)
    .patch(`/api/rentals/bookings/${bookingB.id}/decision`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "CONFIRMED" });
  assert.equal(confirmB.status, 409);
  assert.equal(confirmB.body.code, "RENTAL_OVERLAP");

  const stored = await prisma.rentalBooking.findUniqueOrThrow({ where: { id: bookingB.id } });
  assert.equal(stored.status, "REQUESTED");
});

// Regression: the renter-cancel route used to read the booking's status
// once, then unconditionally overwrite it to CANCELLED — a concurrent
// activate() (driver marks the handover done, CONFIRMED -> ACTIVE, reserves
// the driver) between that read and the write would get silently clobbered
// back to CANCELLED, leaving the driver's freshly-reserved assignment
// orphaned as ACTIVE forever. The conditional update now closes that
// window: if activation wins the race, cancel 409s instead of overwriting.
test("PATCH /api/rentals/bookings/:id/cancel 409s (does not clobber) once the booking has already been activated", async () => {
  const { listing, driver } = await createApprovedListing("driver-sub-cancel-race", 100);
  const renter = await createRider("rider-sub-cancel-race");
  const booking = await prisma.rentalBooking.create({
    data: {
      rentalListingId: listing.id,
      renterId: renter.id,
      vehicleId: listing.vehicleId,
      startAt: new Date("2027-08-01T00:00:00.000Z"),
      endAt: new Date("2027-08-05T00:00:00.000Z"),
      status: "ACTIVE",
      price: 400,
    },
  });
  await prisma.driverAssignment.create({
    data: { driverId: driver.id, assignmentType: "RENTAL", assignmentId: booking.id, vehicleId: listing.vehicleId },
  });

  const token = mockAuthAs({ sub: "rider-sub-cancel-race", groups: ["Rider"] });
  const res = await request(app)
    .patch(`/api/rentals/bookings/${booking.id}/cancel`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 409);

  const stored = await prisma.rentalBooking.findUniqueOrThrow({ where: { id: booking.id } });
  assert.equal(stored.status, "ACTIVE");
  const assignment = await prisma.driverAssignment.findFirst({ where: { driverId: driver.id, status: "ACTIVE" } });
  assert.ok(assignment, "the driver's ACTIVE assignment must not be orphaned/cleared by a failed cancel");
});
