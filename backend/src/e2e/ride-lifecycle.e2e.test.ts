/**
 * A real end-to-end walkthrough of the user_app ride-request flow this
 * session wired up (FindRoute -> SelectRide -> FindDriverScreen ->
 * SearchDriverScreen -> Home's RideViewPopup -> RidesView/RideDetailsView),
 * exercised at the HTTP/route layer against the real local Postgres
 * instance. As in admin-driver-lifecycle.e2e.test.ts, only Cognito JWT
 * signature verification is stubbed (mockAuthAs) — matching, pricing,
 * state transitions, and every Prisma write below are the genuine
 * production code path (services/matching.ts, services/pricing.ts,
 * trips.routes.ts).
 */
import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(async () => {
  await resetDb();
  await prisma.pricingRule.deleteMany();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.pricingRule.deleteMany();
  await prisma.$disconnect();
});

test("ride lifecycle: request -> real fare -> auto-match -> driver progresses trip -> completion -> rider's receipt/history", async () => {
  await prisma.pricingRule.create({
    data: { name: "Standard", baseFare: 500, perKm: 150, perMinute: 25, active: true },
  });

  // A real, ACTIVE, unencumbered driver — otherwise services/matching.ts
  // correctly leaves the trip REQUESTED, which this test would then fail
  // on, proving the matching precondition is real and not assumed.
  const driverToken = mockAuthAs({ sub: "e2e-ride-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Femi", lastName: "Balogun", email: "femi.e2e@example.com" });
  const driverId = driverProfile.body.id as string;
  await prisma.driver.update({ where: { id: driverId }, data: { status: "ACTIVE" } });

  const riderToken = mockAuthAs({ sub: "e2e-ride-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Ngozi", lastName: "Chukwu", email: "ngozi.e2e@example.com" });

  // The exact request shape RideSession.requestTrip() sends: a real
  // distance/duration derived from the rider's selected pickup/destination
  // (see ride_session.dart's haversine + average-speed estimate), not a
  // client-picked fare.
  const distanceKm = 8.4;
  const durationMinutes = (distanceKm / 25) * 60;
  const expectedFare = Math.round((500 + 150 * distanceKm + 25 * durationMinutes) * 100) / 100;

  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "Lekki Phase 1", destination: "Victoria Island", distanceKm, durationMinutes });
  assert.equal(requested.status, 201);
  assert.equal(requested.body.estimatedFare, expectedFare, "fare must be server-computed, not client-supplied");
  assert.equal(requested.body.status, "MATCHED", "the one ACTIVE unencumbered driver must be auto-matched");
  assert.equal(requested.body.driverId, driverId);
  const tripId = requested.body.id as string;

  // Independent re-read — the same call RideSession's poll loop and its
  // immediate post-request fetch make — proves the match is really
  // persisted, including the nested driver/user relation the rider's live
  // status screen (ride_view_popup.dart) renders.
  const fetched = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${riderToken}`);
  assert.equal(fetched.status, 200);
  assert.equal(fetched.body.status, "MATCHED");
  assert.equal(fetched.body.driver.user.firstName, "Femi");

  // A second concurrent request from the same rider is rejected — proves
  // the double-tap/duplicate-request protection is enforced server-side,
  // not only by RideSession.requesting's client-side guard.
  const duplicate = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "Lekki Phase 1", destination: "Ikoyi", distanceKm: 3, durationMinutes: 10 });
  assert.equal(duplicate.status, 409);

  // Driver starts the trip. mockAuthAs replaces the verifier's mock
  // wholesale (see trips.routes.test.ts's owner/stranger pattern) — the
  // rider identity mocked above for the requests up to here means
  // driverToken itself is currently stale, even though the string is
  // unchanged; re-mocking the driver's identity (same deterministic
  // `mock.<sub>` token) makes it valid again for this and the next call.
  const driverTokenAgain = mockAuthAs({ sub: "e2e-ride-driver-1", groups: ["Driver"] });
  assert.equal(driverTokenAgain, driverToken);
  const inProgress = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(inProgress.status, 200);
  assert.equal(inProgress.body.status, "IN_PROGRESS");

  // Driver completes the trip with a real finalFare within the allowed
  // band of the server-established estimate (FINAL_FARE_MIN/MAX_RATIO).
  const finalFare = Math.round(expectedFare * 1.05 * 100) / 100;
  const completed = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "COMPLETED", finalFare });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.status, "COMPLETED");
  assert.equal(completed.body.finalFare, finalFare);

  // Persistence check independent of the response body.
  const persistedTrip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(persistedTrip.status, "COMPLETED");
  assert.equal(persistedTrip.finalFare, finalFare);

  // Completing the trip must release the driver's DriverAssignment so
  // they're matchable again — the real behavior behind driver_app going
  // back to "available" after a ride, not just this trip's own status.
  const driverAfter = await prisma.driver.findUniqueOrThrow({ where: { id: driverId }, include: { assignments: true } });
  assert.ok(
    driverAfter.assignments.every((a) => a.status !== "ACTIVE"),
    "driver must have no ACTIVE assignment once the trip is COMPLETED",
  );

  // Rider's real trip history/receipt — GET /api/trips/mine, exactly what
  // RidesView.dart and RideDetailsView.dart now render. Re-mock the rider
  // identity for the same reason as driverTokenAgain above.
  const riderTokenAgain = mockAuthAs({ sub: "e2e-ride-rider-1", groups: ["Rider"] });
  assert.equal(riderTokenAgain, riderToken);
  const history = await request(app).get("/api/trips/mine").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(history.status, 200);
  assert.equal(history.body.data.length, 1);
  assert.equal(history.body.data[0].id, tripId);
  assert.equal(history.body.data[0].finalFare, finalFare);
  assert.equal(history.body.data[0].driver.user.firstName, "Femi");
});

test("ride lifecycle: rider cancellation before match releases nothing to release and is reflected immediately", async () => {
  const riderToken = mockAuthAs({ sub: "e2e-ride-rider-2", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Tunde", lastName: "Bakare", email: "tunde.e2e@example.com" });

  // No PricingRule and no driver at all — matchDriverToTrip finds none,
  // trip stays REQUESTED, exactly like a real "no drivers nearby" case.
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "Ikeja", destination: "Yaba", estimatedFare: 3000 });
  assert.equal(requested.status, 201);
  assert.equal(requested.body.status, "REQUESTED");
  const tripId = requested.body.id as string;

  const cancelled = await request(app)
    .patch(`/api/trips/${tripId}/cancel`)
    .set("Authorization", `Bearer ${riderToken}`);
  assert.equal(cancelled.status, 200);
  assert.equal(cancelled.body.status, "CANCELLED");

  const persisted = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(persisted.status, "CANCELLED");

  // A second cancel attempt on an already-terminal trip is rejected —
  // proves CANCELLABLE_TRIP_STATUSES is enforced server-side, matching
  // SearchDriverScreen/ride_view_popup.dart only offering "Cancel" while
  // the trip is still REQUESTED/MATCHED.
  const secondCancel = await request(app)
    .patch(`/api/trips/${tripId}/cancel`)
    .set("Authorization", `Bearer ${riderToken}`);
  assert.equal(secondCancel.status, 409);
});
