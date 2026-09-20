import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import type { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { locatedAt, resetDb, restoreAuth } from "../test/helpers";
import {
  MATCHING_LOCATION_MAX_AGE_MS,
  MATCHING_MAX_DISTANCE_KM,
  matchDriverToTrip,
  maybeMatchPendingTrips,
  resetMatchingThrottle,
} from "./matching";
import { LOCATION_PERSIST_MIN_INTERVAL_MS, persistDriverLocation } from "./driver-location";

// Lagos pickup used throughout; every distance below is measured from here.
const PICKUP = { lat: 6.5244, lng: 3.3792 };
// ~0.6 km, ~5 km, ~11 km and ~60 km away respectively (haversine).
const NEAR = { lat: 6.53, lng: 3.3792 };
const MID = { lat: 6.57, lng: 3.3792 };
const FAR = { lat: 6.62, lng: 3.3792 };
const TOO_FAR = { lat: 7.06, lng: 3.3792 };

beforeEach(async () => {
  await resetDb();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await prisma.$disconnect();
});

let seq = 0;
async function seedDriver(data: Omit<Prisma.DriverUncheckedCreateInput, "userId"> = {}) {
  seq += 1;
  const user = await prisma.user.create({
    data: { cognitoSub: `m-sub-${seq}`, role: "DRIVER", firstName: "M", lastName: `${seq}`, email: `m${seq}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id, status: "ACTIVE", isOnline: true, ...data } });
}

async function seedTrip(pickup: { lat: number; lng: number } | null = PICKUP, extra: Record<string, unknown> = {}) {
  seq += 1;
  const rider = await prisma.user.create({
    data: { cognitoSub: `m-rider-${seq}`, role: "RIDER", firstName: "R", lastName: `${seq}`, email: `r${seq}@example.com` },
  });
  return prisma.trip.create({
    data: {
      riderId: rider.id,
      pickup: "X",
      destination: "Y",
      estimatedFare: 10,
      status: "REQUESTED",
      ...(pickup ? { pickupLat: pickup.lat, pickupLng: pickup.lng } : {}),
      ...extra,
    },
  });
}

test("matching offers the nearest fresh-located eligible driver, not the highest rated", async () => {
  const far = await seedDriver({ rating: 5.0, ...locatedAt(FAR.lat, FAR.lng) });
  const near = await seedDriver({ rating: 3.5, ...locatedAt(NEAR.lat, NEAR.lng) });
  const mid = await seedDriver({ rating: 4.9, ...locatedAt(MID.lat, MID.lng) });
  const trip = await seedTrip();

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.status, "OFFERED");
  assert.equal(offered?.driverId, near.id);
  assert.notEqual(offered?.driverId, far.id);
  assert.notEqual(offered?.driverId, mid.id);
});

test("matching breaks a distance tie by rating", async () => {
  const lower = await seedDriver({ rating: 4.0, ...locatedAt(NEAR.lat, NEAR.lng) });
  const higher = await seedDriver({ rating: 4.8, ...locatedAt(NEAR.lat, NEAR.lng) });
  const trip = await seedTrip();

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.driverId, higher.id);
  assert.notEqual(offered?.driverId, lower.id);
});

test("matching ignores drivers whose last position is stale or missing", async () => {
  await seedDriver({ rating: 5.0, ...locatedAt(NEAR.lat, NEAR.lng, MATCHING_LOCATION_MAX_AGE_MS + 1000) });
  await seedDriver({ rating: 5.0 }); // never reported a position
  const fresh = await seedDriver({ rating: 3.0, ...locatedAt(MID.lat, MID.lng) });
  const trip = await seedTrip();

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.driverId, fresh.id);
});

test("matching leaves a trip REQUESTED when every fresh driver is beyond the distance cap", async () => {
  await seedDriver({ rating: 5.0, ...locatedAt(TOO_FAR.lat, TOO_FAR.lng) });
  const trip = await seedTrip();
  assert.ok(MATCHING_MAX_DISTANCE_KM < 50);

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered, null);
  const after = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(after.status, "REQUESTED");
  assert.equal(after.driverId, null);
});

test("matching skips offline, non-ACTIVE, busy and previously-declining drivers even when nearest", async () => {
  const offline = await seedDriver({ isOnline: false, ...locatedAt(NEAR.lat, NEAR.lng) });
  const pending = await seedDriver({ status: "PENDING_REVIEW", ...locatedAt(NEAR.lat, NEAR.lng) });
  const busy = await seedDriver(locatedAt(NEAR.lat, NEAR.lng));
  await seedTrip(PICKUP, { driverId: busy.id, status: "MATCHED" });
  const declined = await seedDriver(locatedAt(NEAR.lat, NEAR.lng));
  const eligible = await seedDriver(locatedAt(MID.lat, MID.lng));
  const trip = await seedTrip(PICKUP, { declinedDriverIds: [declined.id] });

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.driverId, eligible.id);
  for (const d of [offline, pending, busy, declined]) assert.notEqual(offered?.driverId, d.id);
});

test("matching honours the ride category's eligible vehicle classes", async () => {
  await prisma.rideCategory.create({
    data: {
      key: "premium",
      name: "Premium",
      description: "Premium cars",
      baseFare: 1000,
      perKm: 100,
      perMinute: 10,
      sortOrder: 1,
      eligibleVehicleClasses: ["PREMIUM"],
    },
  });
  const nearEconomy = await seedDriver(locatedAt(NEAR.lat, NEAR.lng));
  await prisma.vehicle.create({
    data: { driverId: nearEconomy.id, brand: "K", model: "P", colour: "W", plateNumber: "ECO-1", year: "2019", isPrimary: true, vehicleClass: "ECONOMY" },
  });
  const farPremium = await seedDriver(locatedAt(MID.lat, MID.lng));
  await prisma.vehicle.create({
    data: { driverId: farPremium.id, brand: "M", model: "E", colour: "B", plateNumber: "PRM-1", year: "2022", isPrimary: true, vehicleClass: "PREMIUM" },
  });
  const trip = await seedTrip(PICKUP, { rideCategoryKey: "premium" });

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.driverId, farPremium.id);
});

test("matching falls back to rating order when a legacy trip has no pickup coordinates", async () => {
  await seedDriver({ rating: 4.0, ...locatedAt(NEAR.lat, NEAR.lng) });
  const best = await seedDriver({ rating: 4.9, ...locatedAt(FAR.lat, FAR.lng) });
  const trip = await seedTrip(null);

  const offered = await matchDriverToTrip(trip.id);
  assert.equal(offered?.driverId, best.id);
});

test("two concurrent matches for the same trip produce exactly one offer", async () => {
  await seedDriver(locatedAt(NEAR.lat, NEAR.lng));
  await seedDriver(locatedAt(MID.lat, MID.lng));
  const trip = await seedTrip();

  const results = await Promise.all([matchDriverToTrip(trip.id), matchDriverToTrip(trip.id)]);
  const offers = results.filter((r) => r !== null);
  assert.equal(offers.length, 1);
  const offeredTrips = await prisma.trip.findMany({ where: { status: "OFFERED" } });
  assert.equal(offeredTrips.length, 1);
  assert.equal(offeredTrips[0].id, trip.id);
});

test("persistDriverLocation writes the Driver row, throttles repeat writes and triggers a pending sweep", async () => {
  const driver = await seedDriver();
  const trip = await seedTrip();

  assert.equal(await persistDriverLocation(driver.id, NEAR.lat, NEAR.lng), true);
  // Inside the per-driver throttle window: dropped, row unchanged.
  assert.equal(await persistDriverLocation(driver.id, MID.lat, MID.lng), false);
  const row = await prisma.driver.findUniqueOrThrow({ where: { id: driver.id } });
  assert.equal(row.lastLat, NEAR.lat);
  assert.equal(row.lastLng, NEAR.lng);
  assert.ok(row.lastLocationAt && Date.now() - row.lastLocationAt.getTime() < LOCATION_PERSIST_MIN_INTERVAL_MS);
  // `force` bypasses the throttle.
  assert.equal(await persistDriverLocation(driver.id, MID.lat, MID.lng, { force: true }), true);

  // The sweep kicked off by the first persist offers the waiting trip.
  await maybeMatchPendingTrips();
  const after = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(after.status, "OFFERED");
  assert.equal(after.driverId, driver.id);
});

test("maybeMatchPendingTrips coalesces bursts into a single sweep and throttles the next one", async () => {
  const driver = await seedDriver(locatedAt(NEAR.lat, NEAR.lng));
  const first = await seedTrip();

  // Concurrent callers share the one in-flight sweep.
  const a = maybeMatchPendingTrips();
  const b = maybeMatchPendingTrips();
  assert.equal(a, b);
  await a;
  assert.equal((await prisma.trip.findUniqueOrThrow({ where: { id: first.id } })).driverId, driver.id);

  // A call landing inside the throttle window does no work at all.
  const second = await seedTrip();
  const other = await seedDriver(locatedAt(MID.lat, MID.lng));
  await maybeMatchPendingTrips();
  assert.equal((await prisma.trip.findUniqueOrThrow({ where: { id: second.id } })).status, "REQUESTED");

  // Once the window has passed (test hook), the sweep runs again.
  resetMatchingThrottle();
  await maybeMatchPendingTrips();
  const after = await prisma.trip.findUniqueOrThrow({ where: { id: second.id } });
  assert.equal(after.status, "OFFERED");
  assert.equal(after.driverId, other.id);
});
