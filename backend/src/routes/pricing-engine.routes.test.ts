import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAdminUserStatus } from "../test/helpers";
import { resetRealtimeState } from "../realtime/hub";

beforeEach(async () => {
  resetRealtimeState();
  await resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// ---------------------------------------------------------------------------
// Ride category quotes
// ---------------------------------------------------------------------------

test("GET /api/pricing/categories returns all four reference categories, seeded on first use, each with a real fare", async () => {
  const token = mockAuthAs({ sub: "rider-cat-1", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/pricing/categories")
    .query({ pickupLat: 6.5244, pickupLng: 3.3792, distanceKm: 10, durationMinutes: 20 })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  const keys = res.body.map((c: { categoryKey: string }) => c.categoryKey).sort();
  assert.deepEqual(keys, ["EASE", "ELITE", "LUXE", "SWIFT"]);
  for (const category of res.body) {
    assert.ok(category.estimatedFare > 0, `${category.categoryKey} fare must be a real positive number`);
    assert.equal(category.availability, "UNAVAILABLE"); // no online drivers seeded
    assert.equal(category.pickupEtaMinutes, null);
  }
});

test("GET /api/pricing/categories shows LIMITED once exactly one eligible online driver exists nearby", async () => {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "cat-driver-1", role: "DRIVER", firstName: "D", lastName: "1", email: "catd1@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE", isOnline: true } });
  await prisma.vehicle.create({
    data: { driverId: driver.id, brand: "Toyota", model: "Corolla", colour: "Black", plateNumber: "CAT-001", year: "2020", isPrimary: true },
  });

  const token = mockAuthAs({ sub: "rider-cat-2", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/pricing/categories")
    .query({ pickupLat: 6.5244, pickupLng: 3.3792, distanceKm: 10, durationMinutes: 20 })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  // The seeded categories default to no eligibility restriction, so an
  // online driver with no vehicleClass set still counts as eligible.
  const swift = res.body.find((c: { categoryKey: string }) => c.categoryKey === "SWIFT");
  assert.equal(swift.availability, "LIMITED");
});

// ---------------------------------------------------------------------------
// Ride category admin CRUD
// ---------------------------------------------------------------------------

test("PATCH /api/admin/ride-categories/:id rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-cat-3", groups: ["Rider"] });
  const res = await request(app)
    .patch("/api/admin/ride-categories/anything")
    .set("Authorization", `Bearer ${token}`)
    .send({ active: false });
  assert.equal(res.status, 403);
});

test("Admin can deactivate a ride category, then it drops out of the customer-facing quote", async () => {
  const token = mockAuthAs({ sub: "admin-cat-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const list = await request(app).get("/api/admin/ride-categories").set("Authorization", `Bearer ${token}`);
  assert.equal(list.status, 200);
  const swift = list.body.find((c: { key: string }) => c.key === "SWIFT");

  const patch = await request(app)
    .patch(`/api/admin/ride-categories/${swift.id}`)
    .set("Authorization", `Bearer ${token}`)
    .send({ active: false });
  assert.equal(patch.status, 200);
  assert.equal(patch.body.active, false);

  const riderToken = mockAuthAs({ sub: "rider-cat-4", groups: ["Rider"] });
  const quote = await request(app)
    .get("/api/pricing/categories")
    .query({ pickupLat: 6.5244, pickupLng: 3.3792, distanceKm: 10, durationMinutes: 20 })
    .set("Authorization", `Bearer ${riderToken}`);
  assert.ok(!quote.body.some((c: { categoryKey: string }) => c.categoryKey === "SWIFT"));
});

test("Admin can create a custom ride category with its own commission override", async () => {
  const token = mockAuthAs({ sub: "admin-cat-2", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .post("/api/admin/ride-categories")
    .set("Authorization", `Bearer ${token}`)
    .send({
      key: "XL",
      name: "XL",
      description: "Bigger vehicles",
      baseFare: 1000,
      perKm: 250,
      perMinute: 40,
      minimumFare: 2000,
      commissionRate: 0.15,
    });
  assert.equal(res.status, 201);
  assert.equal(res.body.commissionRate, 0.15);
});

// ---------------------------------------------------------------------------
// Delivery vehicle rates
// ---------------------------------------------------------------------------

test("GET /api/pricing/delivery-quote returns the four reference vehicle classes with real prices from the spec's reference table", async () => {
  const token = mockAuthAs({ sub: "rider-dq-1", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/pricing/delivery-quote")
    .query({ distanceKm: 10, packageSize: "MEDIUM" })
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  const bike = res.body.find((q: { vehicleClass: string }) => q.vehicleClass === "BIKE");
  // 700 initial + 150*10 = 2200 (no default package surcharge configured)
  assert.equal(bike.estimatedFare, 2200);
  const van = res.body.find((q: { vehicleClass: string }) => q.vehicleClass === "VAN");
  // 1800 + 300*10 = 4800
  assert.equal(van.estimatedFare, 4800);
});

test("PATCH /api/admin/delivery-vehicle-rates/:vehicleClass lets Admin change a rate; it's reflected in the next quote", async () => {
  const token = mockAuthAs({ sub: "admin-dq-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const patch = await request(app)
    .patch("/api/admin/delivery-vehicle-rates/bike")
    .set("Authorization", `Bearer ${token}`)
    .send({ initialFee: 900 });
  assert.equal(patch.status, 200);
  assert.equal(patch.body.initialFee, 900);

  const quote = await request(app)
    .get("/api/pricing/delivery-quote")
    .query({ distanceKm: 0, packageSize: "MEDIUM" })
    .set("Authorization", `Bearer ${token}`);
  const bike = quote.body.find((q: { vehicleClass: string }) => q.vehicleClass === "BIKE");
  assert.equal(bike.estimatedFare, 900);
});

// ---------------------------------------------------------------------------
// Commission configuration
// ---------------------------------------------------------------------------

test("GET /api/admin/commission-config seeds RIDE and DELIVERY at the 20% platform default", async () => {
  const token = mockAuthAs({ sub: "admin-cc-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).get("/api/admin/commission-config").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  const ride = res.body.find((c: { service: string }) => c.service === "RIDE");
  const delivery = res.body.find((c: { service: string }) => c.service === "DELIVERY");
  assert.equal(ride.rate, 0.2);
  assert.equal(delivery.rate, 0.2);
});

test("PATCH /api/admin/commission-config/:service rejects a caller without settings:write (Operations Manager)", async () => {
  await prisma.user.create({
    data: { cognitoSub: "ops-cc-1", role: "ADMIN", firstName: "O", lastName: "M", email: "opscc1@example.com", adminRole: "OPERATIONS_MANAGER" },
  });
  const token = mockAuthAs({ sub: "ops-cc-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch("/api/admin/commission-config/RIDE")
    .set("Authorization", `Bearer ${token}`)
    .send({ rate: 0.15 });
  assert.equal(res.status, 403);
});

test("PATCH /api/admin/commission-config/:service rejects a non-Admin caller entirely", async () => {
  const token = mockAuthAs({ sub: "driver-cc-1", groups: ["Driver"] });
  const res = await request(app)
    .patch("/api/admin/commission-config/RIDE")
    .set("Authorization", `Bearer ${token}`)
    .send({ rate: 0.15 });
  assert.equal(res.status, 403);
});

test("PATCH /api/admin/commission-config/:service lets a Super Admin change the rate and writes an audit row", async () => {
  const token = mockAuthAs({ sub: "admin-cc-2", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch("/api/admin/commission-config/RIDE")
    .set("Authorization", `Bearer ${token}`)
    .send({ rate: 0.18 });
  assert.equal(res.status, 200);
  assert.equal(res.body.rate, 0.18);

  const audit = await prisma.auditLog.findFirst({ where: { action: "COMMISSION_RATE_CHANGED" } });
  assert.ok(audit);
  assert.equal((audit!.metadata as { to: number }).to, 0.18);
});

test("PATCH /api/admin/commission-config/:service rejects an out-of-range rate", async () => {
  const token = mockAuthAs({ sub: "admin-cc-3", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch("/api/admin/commission-config/RIDE")
    .set("Authorization", `Bearer ${token}`)
    .send({ rate: 1.5 });
  assert.equal(res.status, 400);
});

// ---------------------------------------------------------------------------
// Financial dashboard
// ---------------------------------------------------------------------------

test("GET /api/admin/financial-dashboard aggregates real ledger rows, not fabricated numbers", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "fd-rider", role: "RIDER", firstName: "R", lastName: "F", email: "fdr@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "fd-driver", role: "DRIVER", firstName: "D", lastName: "F", email: "fdd@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  await prisma.financialTransaction.create({
    data: {
      type: "RIDE_FARE",
      customerId: rider.id,
      driverId: driver.id,
      grossAmount: 5000,
      commissionRate: 0.2,
      commissionAmount: 1000,
      driverEarnings: 4000,
      paymentMethod: "CARD",
      status: "SETTLED",
    },
  });
  await prisma.financialTransaction.create({
    data: {
      type: "DELIVERY_FARE",
      customerId: rider.id,
      driverId: driver.id,
      grossAmount: 10000,
      commissionRate: 0.2,
      commissionAmount: 2000,
      driverEarnings: 8000,
      paymentMethod: "CASH",
      status: "SETTLED",
    },
  });

  const token = mockAuthAs({ sub: "admin-fd-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).get("/api/admin/financial-dashboard").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.grossMarketplaceVolume, 15000);
  assert.equal(res.body.ravelgoRevenue, 3000);
  assert.equal(res.body.driverEarnings, 12000);
  assert.equal(res.body.rideRevenue, 5000);
  assert.equal(res.body.deliveryRevenue, 10000);
  assert.equal(res.body.cashCommissionRecorded, 2000);
});

test("GET /api/admin/financial-dashboard rejects a non-Admin caller", async () => {
  const token = mockAuthAs({ sub: "rider-fd-2", groups: ["Rider"] });
  const res = await request(app).get("/api/admin/financial-dashboard").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

// ---------------------------------------------------------------------------
// Pricing policy
// ---------------------------------------------------------------------------

test("GET /api/admin/pricing-policy returns the reference defaults from the spec on first read", async () => {
  const token = mockAuthAs({ sub: "admin-pp-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).get("/api/admin/pricing-policy").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.rideWaitingFreeSec, 120);
  assert.equal(res.body.rideWaitingPerMinute, 50);
  assert.equal(res.body.rideWaitingMaxFee, 250);
  assert.equal(res.body.rideCancellationFee, 1500);
});

test("PATCH /api/admin/pricing-policy rejects a caller without settings:write", async () => {
  await prisma.user.create({
    data: { cognitoSub: "ops-pp-1", role: "ADMIN", firstName: "O", lastName: "P", email: "opspp1@example.com", adminRole: "OPERATIONS_MANAGER" },
  });
  const token = mockAuthAs({ sub: "ops-pp-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch("/api/admin/pricing-policy")
    .set("Authorization", `Bearer ${token}`)
    .send({ rideCancellationFee: 2000 });
  assert.equal(res.status, 403);
});

test("PATCH /api/admin/pricing-policy lets a Super Admin change the waiting/cancellation policy", async () => {
  const token = mockAuthAs({ sub: "admin-pp-2", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app)
    .patch("/api/admin/pricing-policy")
    .set("Authorization", `Bearer ${token}`)
    .send({ rideCancellationFee: 2000, rideWaitingMaxFee: 300 });
  assert.equal(res.status, 200);
  assert.equal(res.body.rideCancellationFee, 2000);
  assert.equal(res.body.rideWaitingMaxFee, 300);
});
