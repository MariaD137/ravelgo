import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { env } from "../config/env";
import { stripeClient } from "../billing/stripe";
import { mockAuthAs, mockPaymentIntentCreate, restoreAuth, resetDb } from "../test/helpers";

// Build a signed rental-booking webhook the same way Stripe would.
function signedRentalBookingEvent(intentId: string, type: "payment_intent.succeeded" | "payment_intent.payment_failed") {
  const payload = JSON.stringify({
    id: "evt_rental_1",
    object: "event",
    type,
    data: { object: { id: intentId, object: "payment_intent", metadata: { type: "rental_booking" } } },
  });
  const signature = stripeClient.webhooks.generateTestHeaderString({ payload, secret: env.STRIPE_WEBHOOK_SECRET! });
  return { payload, signature };
}

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function createDriverWithVehicle(cognitoSub: string, status: "PENDING_REVIEW" | "ACTIVE" = "ACTIVE") {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  const driver = await prisma.driver.create({ data: { userId: user.id, status } });
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

test("POST /api/rentals rejects a driver pending admin approval", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-1b", "PENDING_REVIEW");
  const token = mockAuthAs({ sub: "driver-sub-1b", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 99.5, location: "Lagos" });

  assert.equal(res.status, 409);
});

test("POST /api/rentals stores real coordinates from the Places-backed picker when provided", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-1c");
  const token = mockAuthAs({ sub: "driver-sub-1c", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 99.5, location: "Ikeja, Lagos, Nigeria", lat: 6.6018, lng: 3.3515 });

  assert.equal(res.status, 201);
  assert.equal(res.body.lat, 6.6018);
  assert.equal(res.body.lng, 3.3515);
});

test("POST /api/rentals still succeeds without coordinates (older client / no picker used)", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-1d");
  const token = mockAuthAs({ sub: "driver-sub-1d", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 99.5, location: "Lagos" });

  assert.equal(res.status, 201);
  assert.equal(res.body.lat, null);
  assert.equal(res.body.lng, null);
});

test("POST /api/rentals rejects an out-of-range coordinate", async () => {
  const { vehicle } = await createDriverWithVehicle("driver-sub-1e");
  const token = mockAuthAs({ sub: "driver-sub-1e", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/rentals")
    .set("Authorization", `Bearer ${token}`)
    .send({ vehicleId: vehicle.id, dailyRate: 99.5, location: "Lagos", lat: 999, lng: 3.4 });

  assert.equal(res.status, 400);
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

test("PATCH /api/rentals/:id/status rejects a Finance Viewer admin and records an audit entry on success", async () => {
  const { driver, vehicle } = await createDriverWithVehicle("driver-sub-7");
  const listing = await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 40, location: "Jos" },
  });
  await prisma.user.create({
    data: { cognitoSub: "finance-rentals", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "fv-rentals@example.com" },
  });

  const financeToken = mockAuthAs({ sub: "finance-rentals", groups: ["Admin"] });
  const denied = await request(app)
    .patch(`/api/rentals/${listing.id}/status`)
    .set("Authorization", `Bearer ${financeToken}`)
    .send({ status: "APPROVED" });
  assert.equal(denied.status, 403);

  restoreAuth();
  const superToken = mockAuthAs({ sub: "super-rentals", groups: ["Admin"] }); // no User row -> SUPER_ADMIN
  const approved = await request(app)
    .patch(`/api/rentals/${listing.id}/status`)
    .set("Authorization", `Bearer ${superToken}`)
    .send({ status: "APPROVED" });
  assert.equal(approved.status, 200);

  const audit = await prisma.auditLog.findFirst({ where: { action: "RENTAL_LISTING_REVIEWED", entityId: listing.id } });
  assert.ok(audit);
});

async function createRider(cognitoSub: string) {
  return prisma.user.create({
    data: { cognitoSub, role: "RIDER", firstName: "R", lastName: "I", email: `${cognitoSub}@example.com` },
  });
}

async function createApprovedListing(driverSub: string, dailyRate = 100) {
  const { driver, vehicle } = await createDriverWithVehicle(driverSub);
  return prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate, location: "Lagos", status: "APPROVED" },
  });
}

test("POST /api/rentals/:id/book computes price server-side and rejects a client-supplied price", async () => {
  const listing = await createApprovedListing("driver-sub-7", 100);
  await createRider("rider-sub-2");
  const token = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({
      startDate: "2027-01-01T00:00:00.000Z",
      endDate: "2027-01-04T00:00:00.000Z",
      totalPrice: 1, // must be ignored — server computes from dailyRate * days
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_PAYMENT");
  assert.equal(res.body.days, 3);
  assert.equal(res.body.totalPrice, 300);
});

test("POST /api/rentals/:id/book rejects an unapproved listing", async () => {
  const { driver, vehicle } = await createDriverWithVehicle("driver-sub-8");
  const listing = await prisma.rentalListing.create({
    data: { driverId: driver.id, vehicleId: vehicle.id, dailyRate: 50, location: "Lagos", status: "PENDING_APPROVAL" },
  });
  await createRider("rider-sub-3");
  const token = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-01-01T00:00:00.000Z", endDate: "2027-01-02T00:00:00.000Z" });

  assert.equal(res.status, 409);
});

test("POST /api/rentals/:id/book rejects overlapping dates on the same vehicle (no double-booking)", async () => {
  const listing = await createApprovedListing("driver-sub-9", 100);
  await createRider("rider-sub-4");
  const tokenA = mockAuthAs({ sub: "rider-sub-4", groups: ["Rider"] });
  const first = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${tokenA}`)
    .send({ startDate: "2027-02-01T00:00:00.000Z", endDate: "2027-02-05T00:00:00.000Z" });
  assert.equal(first.status, 201);

  restoreAuth();
  await createRider("rider-sub-5");
  const tokenB = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const overlapping = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${tokenB}`)
    .send({ startDate: "2027-02-03T00:00:00.000Z", endDate: "2027-02-06T00:00:00.000Z" });
  assert.equal(overlapping.status, 409);

  const nonOverlapping = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${tokenB}`)
    .send({ startDate: "2027-02-05T00:00:00.000Z", endDate: "2027-02-07T00:00:00.000Z" });
  assert.equal(nonOverlapping.status, 201);
});

test("POST /api/rental-bookings/:id/pay with WALLET debits the renter's balance and confirms the booking", async () => {
  const listing = await createApprovedListing("driver-sub-10", 100);
  const rider = await createRider("rider-sub-6");
  await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 100000 } }); // $1000
  const token = mockAuthAs({ sub: "rider-sub-6", groups: ["Rider"] });

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-03-01T00:00:00.000Z", endDate: "2027-03-03T00:00:00.000Z" });
  assert.equal(book.status, 201);
  assert.equal(book.body.totalPrice, 200);

  const pay = await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "WALLET" });

  assert.equal(pay.status, 201);
  assert.equal(pay.body.status, "CONFIRMED");
  assert.equal(pay.body.paymentStatus, "SUCCEEDED");

  const wallet = await prisma.walletAccount.findUnique({ where: { userId: rider.id } });
  assert.equal(wallet?.balanceCents, 100000 - 20000);

  const notifications = await prisma.notification.findMany({ where: { userId: rider.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "RENTAL_CONFIRMED");
  assert.equal(notifications[0].referenceType, "RENTAL_BOOKING");
  assert.equal(notifications[0].referenceId, book.body.id);
});

test("POST /api/rental-bookings/:id/pay with WALLET rejects insufficient balance", async () => {
  const listing = await createApprovedListing("driver-sub-11", 100);
  const rider = await createRider("rider-sub-7");
  await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 100 } }); // $1, not enough
  const token = mockAuthAs({ sub: "rider-sub-7", groups: ["Rider"] });

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-04-01T00:00:00.000Z", endDate: "2027-04-02T00:00:00.000Z" });
  assert.equal(book.status, 201);

  const pay = await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "WALLET" });

  assert.equal(pay.status, 402);
});

test("POST /api/rental-bookings/:id/pay with CARD creates a real PaymentIntent and stays PENDING_PAYMENT until the webhook confirms it", async () => {
  const listing = await createApprovedListing("driver-sub-12", 100);
  await createRider("rider-sub-8");
  const token = mockAuthAs({ sub: "rider-sub-8", groups: ["Rider"] });
  const intentId = mockPaymentIntentCreate();

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-05-01T00:00:00.000Z", endDate: "2027-05-02T00:00:00.000Z" });

  const pay = await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });

  assert.equal(pay.status, 201);
  assert.equal(pay.body.status, "PENDING_PAYMENT");
  assert.equal(pay.body.providerReference, intentId);
  assert.ok(pay.body.clientSecret);
});

test("POST /api/rental-bookings/:id/pay rejects a caller who doesn't own the booking", async () => {
  const listing = await createApprovedListing("driver-sub-13", 100);
  const rider = await createRider("rider-sub-9");
  await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 100000 } });
  const ownerToken = mockAuthAs({ sub: "rider-sub-9", groups: ["Rider"] });
  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${ownerToken}`)
    .send({ startDate: "2027-06-01T00:00:00.000Z", endDate: "2027-06-02T00:00:00.000Z" });

  restoreAuth();
  await createRider("rider-sub-10");
  const strangerToken = mockAuthAs({ sub: "rider-sub-10", groups: ["Rider"] });
  const pay = await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ method: "WALLET" });

  assert.equal(pay.status, 403);
});

test("GET /api/rental-bookings/mine only lists my own bookings", async () => {
  const listing = await createApprovedListing("driver-sub-14", 100);
  const riderA = await createRider("rider-sub-11");
  const tokenA = mockAuthAs({ sub: "rider-sub-11", groups: ["Rider"] });
  await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${tokenA}`)
    .send({ startDate: "2027-07-01T00:00:00.000Z", endDate: "2027-07-02T00:00:00.000Z" });

  restoreAuth();
  await createRider("rider-sub-12");
  const tokenB = mockAuthAs({ sub: "rider-sub-12", groups: ["Rider"] });
  const res = await request(app).get("/api/rental-bookings/mine").set("Authorization", `Bearer ${tokenB}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 0);

  restoreAuth();
  const tokenA2 = mockAuthAs({ sub: "rider-sub-11", groups: ["Rider"] });
  const resA = await request(app).get("/api/rental-bookings/mine").set("Authorization", `Bearer ${tokenA2}`);
  assert.equal(resA.status, 200);
  assert.equal(resA.body.length, 1);
  assert.equal(resA.body[0].renterId, riderA.id);
});

test("PATCH /api/rental-bookings/:id/cancel refunds a WALLET payment back to the renter's balance", async () => {
  const listing = await createApprovedListing("driver-sub-15", 100);
  const rider = await createRider("rider-sub-13");
  await prisma.walletAccount.create({ data: { userId: rider.id, balanceCents: 100000 } });
  const token = mockAuthAs({ sub: "rider-sub-13", groups: ["Rider"] });

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-08-01T00:00:00.000Z", endDate: "2027-08-03T00:00:00.000Z" });
  await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "WALLET" });

  const cancel = await request(app)
    .patch(`/api/rental-bookings/${book.body.id}/cancel`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(cancel.status, 200);
  assert.equal(cancel.body.status, "CANCELLED");
  assert.equal(cancel.body.paymentStatus, "REFUNDED");

  const wallet = await prisma.walletAccount.findUnique({ where: { userId: rider.id } });
  assert.equal(wallet?.balanceCents, 100000); // fully refunded

  const notifications = await prisma.notification.findMany({ where: { userId: rider.id }, orderBy: { createdAt: "asc" } });
  assert.deepEqual(notifications.map((n) => n.type), ["RENTAL_CONFIRMED", "RENTAL_CANCELLED"]);
});

test("a CARD rental booking is only CONFIRMED once the signed webhook confirms the charge", async () => {
  const listing = await createApprovedListing("driver-sub-16", 100);
  const rider = await createRider("rider-sub-14");
  const token = mockAuthAs({ sub: "rider-sub-14", groups: ["Rider"] });
  const intentId = mockPaymentIntentCreate("pi_rental_1");

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-09-01T00:00:00.000Z", endDate: "2027-09-02T00:00:00.000Z" });
  const pay = await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });
  assert.equal(pay.body.status, "PENDING_PAYMENT");

  const { payload, signature } = signedRentalBookingEvent(intentId, "payment_intent.succeeded");
  const hook = await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(payload);
  assert.equal(hook.status, 200);

  const confirmed = await prisma.rentalBooking.findUnique({ where: { id: book.body.id } });
  assert.equal(confirmed?.status, "CONFIRMED");
  assert.equal(confirmed?.paymentStatus, "SUCCEEDED");

  const notifications = await prisma.notification.findMany({ where: { userId: rider.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "RENTAL_CONFIRMED");
});

test("a failed CARD rental booking webhook marks the payment FAILED and leaves the booking unconfirmed", async () => {
  const listing = await createApprovedListing("driver-sub-17", 100);
  const rider = await createRider("rider-sub-15");
  const token = mockAuthAs({ sub: "rider-sub-15", groups: ["Rider"] });
  const intentId = mockPaymentIntentCreate("pi_rental_2");

  const book = await request(app)
    .post(`/api/rentals/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ startDate: "2027-10-01T00:00:00.000Z", endDate: "2027-10-02T00:00:00.000Z" });
  await request(app)
    .post(`/api/rental-bookings/${book.body.id}/pay`)
    .set("Authorization", `Bearer ${token}`)
    .send({ method: "CARD" });

  const { payload, signature } = signedRentalBookingEvent(intentId, "payment_intent.payment_failed");
  await request(app)
    .post("/api/billing/webhook")
    .set("Content-Type", "application/json")
    .set("stripe-signature", signature)
    .send(payload);

  const failed = await prisma.rentalBooking.findUnique({ where: { id: book.body.id } });
  assert.equal(failed?.status, "PENDING_PAYMENT");
  assert.equal(failed?.paymentStatus, "FAILED");

  const notifications = await prisma.notification.findMany({ where: { userId: rider.id } });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].type, "PAYMENT_FAILED");
});
