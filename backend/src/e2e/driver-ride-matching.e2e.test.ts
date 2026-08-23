/**
 * The real end-to-end walkthrough this task (DRIVER APP REAL MATCHING
 * INTEGRATION) exists to prove: a real rider request results in a real
 * backend match, a real driver-app-visible assignment, a real driver
 * acceptance, and a real database state change — driven entirely through
 * the same HTTP endpoints driver_app's DriverSession now calls
 * (PATCH /drivers/me/online, GET /drivers/me/assignment, GET /trips/:id,
 * PATCH /trips/:id/status), against the real local Postgres instance. As
 * in the other e2e files, only Cognito JWT signature verification is
 * stubbed (mockAuthAs) — matching, availability, and every state
 * transition below are the genuine production code path.
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

test("driver-visible ride matching: online -> real match -> driver discovers it -> accepts -> completes -> available again", async () => {
  await prisma.pricingRule.create({
    data: { name: "Standard", baseFare: 500, perKm: 150, perMinute: 25, active: true },
  });

  // 1-2. Create/authenticate driver and rider.
  const driverToken = mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Tayo", lastName: "Ojo", email: "tayo.match@example.com" });
  assert.equal(driverProfile.body.online, false, "a driver starts offline until they explicitly go online");
  await prisma.driver.update({ where: { id: driverProfile.body.id }, data: { status: "ACTIVE" } });

  // 3. Driver becomes available — the real backend effect of the
  // driver_home_screen online switch (DriverSession.setOnline()).
  const goOnline = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ online: true });
  assert.equal(goOnline.status, 200);
  assert.equal(goOnline.body.online, true);

  // Before any match: the driver's own polling endpoint correctly reports
  // no active assignment.
  const noneYet = await request(app).get("/api/drivers/me/assignment").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(noneYet.status, 200);
  assert.equal(noneYet.body, null);

  // 4-6. Rider requests a real ride; the backend's matching engine assigns
  // the online driver synchronously.
  const riderToken = mockAuthAs({ sub: "e2e-match-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Bisi", lastName: "Ade", email: "bisi.match@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "Ikeja", destination: "Yaba", distanceKm: 6, durationMinutes: 15 });
  assert.equal(requested.status, 201);
  assert.equal(requested.body.status, "MATCHED");
  const tripId = requested.body.id as string;

  // 7. Driver discovers the assignment through the exact polling endpoint
  // DriverSession._poll() calls — no push required for this to work.
  const driverTokenAgain = mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const discovered = await request(app)
    .get("/api/drivers/me/assignment")
    .set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(discovered.status, 200);
  assert.equal(discovered.body.assignmentType, "RIDE");
  assert.equal(discovered.body.assignmentId, tripId);
  assert.equal(discovered.body.status, "ACTIVE");

  // 8. Driver "accepts" — DriverSession.acceptPendingRide()'s real
  // confirmation step: re-fetch the trip and verify it's still MATCHED
  // and theirs before treating it as accepted. There is no separate
  // accept endpoint — matching already committed the assignment.
  const confirmFetch = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(confirmFetch.status, 200);
  assert.equal(confirmFetch.body.status, "MATCHED");
  assert.equal(confirmFetch.body.driver.user.firstName, "Tayo");

  // 9. Verify database assignment directly.
  const assignmentRow = await prisma.driverAssignment.findFirstOrThrow({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(assignmentRow.assignmentType, "RIDE");
  assert.equal(assignmentRow.assignmentId, tripId);

  // 10. Rider sees the accepted/matched state. mockAuthAs replaces the
  // verifier's mock wholesale (see trips.routes.test.ts's owner/stranger
  // pattern) — driverTokenAgain was mocked most recently above, so the
  // rider identity must be re-established before reusing riderToken.
  mockAuthAs({ sub: "e2e-match-rider-1", groups: ["Rider"] });
  const riderView = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${riderToken}`);
  assert.equal(riderView.body.status, "MATCHED");

  // 11-12. Driver transitions the ride lifecycle; rider sees each update.
  mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const inProgress = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverTokenAgain}`)
    .send({ status: "IN_PROGRESS" });
  assert.equal(inProgress.status, 200);
  assert.equal(inProgress.body.status, "IN_PROGRESS");

  mockAuthAs({ sub: "e2e-match-rider-1", groups: ["Rider"] });
  const riderSeesProgress = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${riderToken}`);
  assert.equal(riderSeesProgress.body.status, "IN_PROGRESS");

  // 13. Driver completes the ride.
  mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const finalFare = requested.body.estimatedFare as number;
  const completed = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverTokenAgain}`)
    .send({ status: "COMPLETED", finalFare });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.status, "COMPLETED");

  // 14. Verify final database state independent of any response body.
  const persistedTrip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(persistedTrip.status, "COMPLETED");
  assert.equal(persistedTrip.finalFare, finalFare);

  // 15. Driver becomes available again — the ACTIVE assignment was
  // released by completing the trip, so a new poll finds nothing pending
  // and a fresh match is possible.
  const assignmentAfter = await prisma.driverAssignment.findFirst({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(assignmentAfter, null);

  const finalPoll = await request(app)
    .get("/api/drivers/me/assignment")
    .set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(finalPoll.status, 200);
  assert.equal(finalPoll.body, null);
});

test("driver decline: a driver can release a MATCHED ride via the real status endpoint, freeing them for a new match", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-decline-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Kunle", lastName: "Bello", email: "kunle.decline@example.com" });
  await prisma.driver.update({
    where: { id: driverProfile.body.id },
    data: { status: "ACTIVE", online: true },
  });

  const riderToken = mockAuthAs({ sub: "e2e-decline-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Nkem", lastName: "Obi", email: "nkem.decline@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1500 });
  assert.equal(requested.body.status, "MATCHED");
  const tripId = requested.body.id as string;

  const driverTokenAgain = mockAuthAs({ sub: "e2e-decline-driver-1", groups: ["Driver"] });
  const decline = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverTokenAgain}`)
    .send({ status: "CANCELLED" });
  assert.equal(decline.status, 200);
  assert.equal(decline.body.status, "CANCELLED");

  const assignmentAfter = await prisma.driverAssignment.findFirst({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(assignmentAfter, null, "declining must release the driver's assignment");

  const poll = await request(app).get("/api/drivers/me/assignment").set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(poll.body, null);
});

test("an offline (but ACTIVE) driver is never matched — going offline actually affects real matching, not just local UI", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-offline-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Seun", lastName: "Fash", email: "seun.offline@example.com" });
  // ACTIVE (admin-approved) but never toggled online.
  await prisma.driver.update({ where: { id: driverProfile.body.id }, data: { status: "ACTIVE" } });

  const riderToken = mockAuthAs({ sub: "e2e-offline-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Wale", lastName: "Yusuf", email: "wale.offline@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1200 });

  assert.equal(requested.status, 201);
  assert.equal(requested.body.status, "REQUESTED", "no online driver exists, so the trip must stay unmatched");
  assert.equal(requested.body.driverId, null);
});
