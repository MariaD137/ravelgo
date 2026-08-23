/**
 * The real end-to-end walkthrough this task (DRIVER OFFER / ACCEPTANCE-RATE
 * MODEL) exists to prove: a real rider request results in a real backend
 * OFFER (never an automatic match), a real driver-app-visible offer, a real
 * driver accept-or-decline decision, and a real database state change —
 * driven entirely through the same HTTP endpoints driver_app's
 * DriverSession calls (PATCH /drivers/me/online, GET /drivers/me/offer,
 * PATCH /trip-offers/:id/accept|decline, GET /trips/:id,
 * PATCH /trips/:id/status), against the real local Postgres instance. As
 * in the other e2e files, only Cognito JWT signature verification is
 * stubbed (mockAuthAs) — matching, availability, and every state
 * transition below are the genuine production code path.
 */
import assert from "node:assert/strict";
import { after, afterEach, beforeEach, mock, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { verifier } from "../middleware/auth";
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

test("driver-visible ride matching: online -> real offer -> driver discovers it -> accepts -> completes -> available again", async () => {
  await prisma.pricingRule.create({
    data: { name: "Standard", baseFare: 500, perKm: 150, perMinute: 25, active: true },
  });

  // 1-2. Create/authenticate driver and rider. A newly-created driver
  // starts PENDING_REVIEW — admin approval is a one-time account-lifecycle
  // step, separate from any individual ride (see §11 of
  // DRIVER_OFFER_ACCEPTANCE_READINESS.md).
  const driverToken = mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Tayo", lastName: "Ojo", email: "tayo.match@example.com" });
  assert.equal(driverProfile.body.status, "PENDING_REVIEW");
  assert.equal(driverProfile.body.online, false, "a driver starts offline until they explicitly go online");

  // A PENDING_REVIEW driver cannot go online at all.
  const blockedOnline = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ online: true });
  assert.equal(blockedOnline.status, 403);

  // Admin approves — the one-time eligibility step.
  await prisma.driver.update({ where: { id: driverProfile.body.id }, data: { status: "ACTIVE" } });

  // 3. Driver becomes available — the real backend effect of the
  // driver_home_screen online switch (DriverSession.setOnline()).
  const goOnline = await request(app)
    .patch("/api/drivers/me/online")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ online: true });
  assert.equal(goOnline.status, 200);
  assert.equal(goOnline.body.online, true);

  // Before any ride: the driver's own polling endpoints correctly report
  // no active assignment and no pending offer.
  const noneYet = await request(app).get("/api/drivers/me/assignment").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(noneYet.body, null);
  const noOfferYet = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${driverToken}`);
  assert.equal(noOfferYet.body, null);

  // 4-5. Rider requests a real ride; the backend sends a real OFFER to the
  // online, ACTIVE driver — never an automatic match.
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
  assert.equal(requested.body.status, "REQUESTED", "a real offer went out; the trip is not auto-matched");
  assert.equal(requested.body.driverId, null);
  const tripId = requested.body.id as string;

  // 6-7. Driver discovers the offer through the exact polling endpoint
  // DriverSession._poll() calls — no push required for this to work.
  const driverTokenAgain = mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const discovered = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(discovered.status, 200);
  assert.equal(discovered.body.tripId, tripId);
  assert.equal(discovered.body.status, "OFFERED");
  const offerId = discovered.body.id as string;

  // Driver looks at the real trip details before deciding (pickup/
  // destination/fare shown in the real offer sheet).
  const tripDetail = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(tripDetail.body.pickup, "Ikeja");
  assert.equal(tripDetail.body.destination, "Yaba");
  assert.ok(tripDetail.body.estimatedFare > 0);

  // 8. Driver ACCEPTS — the real, only way this trip becomes MATCHED.
  const accepted = await request(app)
    .patch(`/api/trip-offers/${offerId}/accept`)
    .set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.status, "MATCHED");
  assert.equal(accepted.body.driverId, driverProfile.body.id);

  // 9. Verify the acceptance was really recorded on the offer itself.
  const offerRow = await prisma.tripOffer.findUniqueOrThrow({ where: { id: offerId } });
  assert.equal(offerRow.status, "ACCEPTED");
  assert.ok(offerRow.respondedAt);

  // 10. Verify database assignment directly.
  const assignmentRow = await prisma.driverAssignment.findFirstOrThrow({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(assignmentRow.assignmentType, "RIDE");
  assert.equal(assignmentRow.assignmentId, tripId);

  // 11. Driver remains ACTIVE — accepting a ride never touches account status.
  const driverAfterAccept = await prisma.driver.findUniqueOrThrow({ where: { id: driverProfile.body.id } });
  assert.equal(driverAfterAccept.status, "ACTIVE");

  // 12. Rider sees the accepted/matched state. mockAuthAs replaces the
  // verifier's mock wholesale (see trips.routes.test.ts's owner/stranger
  // pattern) — driverTokenAgain was mocked most recently above, so the
  // rider identity must be re-established before reusing riderToken.
  mockAuthAs({ sub: "e2e-match-rider-1", groups: ["Rider"] });
  const riderView = await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${riderToken}`);
  assert.equal(riderView.body.status, "MATCHED");

  // 13-14. Driver transitions the ride lifecycle; rider sees each update.
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

  // 15. Driver completes the ride.
  mockAuthAs({ sub: "e2e-match-driver-1", groups: ["Driver"] });
  const finalFare = requested.body.estimatedFare as number;
  const completed = await request(app)
    .patch(`/api/trips/${tripId}/status`)
    .set("Authorization", `Bearer ${driverTokenAgain}`)
    .send({ status: "COMPLETED", finalFare });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.status, "COMPLETED");

  // 16. Verify final database state independent of any response body.
  const persistedTrip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(persistedTrip.status, "COMPLETED");
  assert.equal(persistedTrip.finalFare, finalFare);

  // 17. Driver becomes available again — the ACTIVE assignment was
  // released by completing the trip, so a new poll finds nothing pending
  // and a fresh offer is possible.
  const assignmentAfter = await prisma.driverAssignment.findFirst({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(assignmentAfter, null);

  const finalPoll = await request(app)
    .get("/api/drivers/me/assignment")
    .set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.equal(finalPoll.status, 200);
  assert.equal(finalPoll.body, null);

  // 18. Acceptance rate reflects this one real acceptance.
  const profileAfter = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${driverTokenAgain}`);
  assert.deepEqual(profileAfter.body.acceptanceStats, {
    totalOffers: 1,
    acceptedOffers: 1,
    declinedOffers: 0,
    expiredOffers: 0,
    acceptanceRate: 1,
  });
});

test("driver decline: releases the offer, the driver stays available, and the trip is offered to the next eligible driver", async () => {
  const declinerToken = mockAuthAs({ sub: "e2e-decline-driver-1", groups: ["Driver"] });
  const declinerProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${declinerToken}`)
    .send({ firstName: "Kunle", lastName: "Bello", email: "kunle.decline@example.com" });
  await prisma.driver.update({
    where: { id: declinerProfile.body.id },
    // Highest-rated so matching offers them first.
    data: { status: "ACTIVE", online: true, rating: 4.9 },
  });

  const secondDriverToken = mockAuthAs({ sub: "e2e-decline-driver-2", groups: ["Driver"] });
  const secondDriverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${secondDriverToken}`)
    .send({ firstName: "Ada", lastName: "Eze", email: "ada.decline@example.com" });
  await prisma.driver.update({
    where: { id: secondDriverProfile.body.id },
    data: { status: "ACTIVE", online: true, rating: 4.5 },
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
  assert.equal(requested.body.status, "REQUESTED");
  const tripId = requested.body.id as string;

  // The higher-rated driver was offered first.
  const declinerTokenAgain = mockAuthAs({ sub: "e2e-decline-driver-1", groups: ["Driver"] });
  const firstOffer = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${declinerTokenAgain}`);
  assert.equal(firstOffer.body.tripId, tripId);

  const decline = await request(app)
    .patch(`/api/trip-offers/${firstOffer.body.id}/decline`)
    .set("Authorization", `Bearer ${declinerTokenAgain}`);
  assert.equal(decline.status, 200);
  assert.equal(decline.body.status, "DECLINED");

  // Declining is recorded on the offer itself, and never creates a
  // DriverAssignment — an offer is only ever a proposal.
  const declinedOfferRow = await prisma.tripOffer.findUniqueOrThrow({ where: { id: firstOffer.body.id } });
  assert.equal(declinedOfferRow.status, "DECLINED");
  assert.ok(declinedOfferRow.respondedAt);
  const declinerAssignment = await prisma.driverAssignment.findFirst({ where: { driverId: declinerProfile.body.id } });
  assert.equal(declinerAssignment, null);

  // The decliner's own account is completely untouched — still ACTIVE and
  // online, and (checked below) eligible for a brand new, different offer.
  const declinerAfter = await prisma.driver.findUniqueOrThrow({ where: { id: declinerProfile.body.id } });
  assert.equal(declinerAfter.status, "ACTIVE");
  assert.equal(declinerAfter.online, true);
  const declinerOfferAfter = await request(app)
    .get("/api/drivers/me/offer")
    .set("Authorization", `Bearer ${declinerTokenAgain}`);
  assert.equal(declinerOfferAfter.body, null, "the decliner has no lingering offer for the trip they just turned down");

  // The trip was real-time handed to the next eligible driver, not
  // cancelled and not left stuck.
  const secondTokenAgain = mockAuthAs({ sub: "e2e-decline-driver-2", groups: ["Driver"] });
  const secondOffer = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${secondTokenAgain}`);
  assert.equal(secondOffer.body.tripId, tripId);
  assert.equal(secondOffer.body.status, "OFFERED");

  const stillRequested = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(stillRequested.status, "REQUESTED");
  assert.equal(stillRequested.driverId, null);

  // Second driver accepts — proves the handoff produces a real, working match.
  const secondAccept = await request(app)
    .patch(`/api/trip-offers/${secondOffer.body.id}/accept`)
    .set("Authorization", `Bearer ${secondTokenAgain}`);
  assert.equal(secondAccept.status, 200);
  assert.equal(secondAccept.body.status, "MATCHED");
  assert.equal(secondAccept.body.driverId, secondDriverProfile.body.id);

  // A stale accept attempt by the driver who declined must not succeed
  // (defense in depth — declineOffer already marked it DECLINED). mockAuthAs
  // replaces the verifier's mock wholesale — re-mock the decliner's
  // identity since secondTokenAgain was mocked most recently above.
  const declinerTokenOnceMore = mockAuthAs({ sub: "e2e-decline-driver-1", groups: ["Driver"] });
  const staleAccept = await request(app)
    .patch(`/api/trip-offers/${firstOffer.body.id}/accept`)
    .set("Authorization", `Bearer ${declinerTokenOnceMore}`);
  assert.equal(staleAccept.status, 409);
});

test("an offline (but ACTIVE) driver is never offered a ride — going offline actually affects real matching, not just local UI", async () => {
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
  assert.equal(requested.body.status, "REQUESTED", "no online driver exists, so the trip must stay unoffered");
  assert.equal(requested.body.driverId, null);
  const offers = await prisma.tripOffer.count({ where: { tripId: requested.body.id } });
  assert.equal(offers, 0);
});

test("PENDING_REVIEW driver is never offered a ride, even if online were somehow forced true", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-pending-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Tunde", lastName: "Bakare", email: "tunde.pending@example.com" });
  assert.equal(driverProfile.body.status, "PENDING_REVIEW");
  // Simulates any bypass of the online-toggle's own status gate (defense
  // in depth — offerNextDriver's own eligibility query must independently
  // enforce ACTIVE, not rely solely on the online-toggle route's check).
  await prisma.driver.update({ where: { id: driverProfile.body.id }, data: { online: true } });

  const riderToken = mockAuthAs({ sub: "e2e-pending-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Chidi", lastName: "Nwosu", email: "chidi.pending@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1200 });

  assert.equal(requested.body.status, "REQUESTED");
  const offers = await prisma.tripOffer.count({ where: { driverId: driverProfile.body.id } });
  assert.equal(offers, 0);
});

test("SUSPENDED driver is never offered a ride", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-suspended-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Bola", lastName: "Ige", email: "bola.suspended@example.com" });
  await prisma.driver.update({
    where: { id: driverProfile.body.id },
    data: { status: "SUSPENDED", online: true },
  });

  const riderToken = mockAuthAs({ sub: "e2e-suspended-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Femi", lastName: "Ola", email: "femi.suspended@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1200 });

  assert.equal(requested.body.status, "REQUESTED");
  const offers = await prisma.tripOffer.count({ where: { driverId: driverProfile.body.id } });
  assert.equal(offers, 0);
});

test("offer expiration: an unanswered offer past its TTL is marked EXPIRED (not silently accepted) and re-offered to the next driver", async () => {
  const firstToken = mockAuthAs({ sub: "e2e-expire-driver-1", groups: ["Driver"] });
  const firstProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${firstToken}`)
    .send({ firstName: "Ola", lastName: "Wale", email: "ola.expire@example.com" });
  await prisma.driver.update({ where: { id: firstProfile.body.id }, data: { status: "ACTIVE", online: true, rating: 4.9 } });

  const secondToken = mockAuthAs({ sub: "e2e-expire-driver-2", groups: ["Driver"] });
  const secondProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${secondToken}`)
    .send({ firstName: "Chika", lastName: "Obi", email: "chika.expire@example.com" });
  await prisma.driver.update({ where: { id: secondProfile.body.id }, data: { status: "ACTIVE", online: true, rating: 4.5 } });

  const riderToken = mockAuthAs({ sub: "e2e-expire-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Ifeoma", lastName: "Chukwu", email: "ifeoma.expire@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1500 });
  const tripId = requested.body.id as string;

  const firstOffer = await prisma.tripOffer.findFirstOrThrow({ where: { tripId } });
  assert.equal(firstOffer.driverId, firstProfile.body.id);

  // Force the offer's own expiresAt into the past — the real timeout path
  // (no sleeping in this test), then let the rider's own trip poll be the
  // thing that lazily catches it, exactly as it would from a real client.
  await prisma.tripOffer.update({ where: { id: firstOffer.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
  mockAuthAs({ sub: "e2e-expire-rider-1", groups: ["Rider"] });
  await request(app).get(`/api/trips/${tripId}`).set("Authorization", `Bearer ${riderToken}`);

  const firstOfferAfter = await prisma.tripOffer.findUniqueOrThrow({ where: { id: firstOffer.id } });
  assert.equal(firstOfferAfter.status, "EXPIRED", "an unanswered, timed-out offer must be EXPIRED, never silently ACCEPTED");
  assert.ok(firstOfferAfter.respondedAt);

  // The second driver was automatically offered the same trip.
  const secondTokenAgain = mockAuthAs({ sub: "e2e-expire-driver-2", groups: ["Driver"] });
  const secondOffer = await request(app).get("/api/drivers/me/offer").set("Authorization", `Bearer ${secondTokenAgain}`);
  assert.equal(secondOffer.body.tripId, tripId);
  assert.equal(secondOffer.body.status, "OFFERED");

  // The first driver can no longer act on the expired offer.
  const staleAccept = await request(app)
    .patch(`/api/trip-offers/${firstOffer.id}/accept`)
    .set("Authorization", `Bearer ${mockAuthAs({ sub: "e2e-expire-driver-1", groups: ["Driver"] })}`);
  assert.equal(staleAccept.status, 409);

  // Acceptance-rate accounting: the first driver's expiry is tracked
  // separately from both accepted and declined, never silently counted
  // as an acceptance.
  const firstProfileAfter = await request(app)
    .get("/api/drivers/me")
    .set("Authorization", `Bearer ${mockAuthAs({ sub: "e2e-expire-driver-1", groups: ["Driver"] })}`);
  assert.deepEqual(firstProfileAfter.body.acceptanceStats, {
    totalOffers: 1,
    acceptedOffers: 0,
    declinedOffers: 0,
    expiredOffers: 1,
    acceptanceRate: 0,
  });

  // Only one Trip row exists throughout — the handoff never duplicated it.
  const tripCount = await prisma.trip.count({ where: { id: tripId } });
  assert.equal(tripCount, 1);
});

test("acceptance rate: computed correctly across a mix of accepted, declined, and expired offers", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-rate-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Rate", lastName: "Test", email: "rate.test@example.com" });
  const driverId = driverProfile.body.id as string;
  await prisma.driver.update({ where: { id: driverId }, data: { status: "ACTIVE", online: true } });

  // A distinct rider per trip — Trip_riderId_open_unique allows at most one
  // open (REQUESTED/MATCHED/IN_PROGRESS) trip per rider, and this test's
  // point is the driver's aggregate offer stats, not shared rider identity.
  async function newRider(label: string) {
    return prisma.user.create({
      data: { cognitoSub: `e2e-rate-rider-${label}`, role: "RIDER", firstName: "R", lastName: "T", email: `rt-${label}@example.com` },
    });
  }

  // No offers yet: null, not 0% — "no data" must never look like a bad record.
  const beforeAny = await request(app).get("/api/drivers/me").set("Authorization", `Bearer ${driverToken}`);
  assert.deepEqual(beforeAny.body.acceptanceStats, {
    totalOffers: 0,
    acceptedOffers: 0,
    declinedOffers: 0,
    expiredOffers: 0,
    acceptanceRate: null,
  });

  // 2 accepted, 1 declined, 1 expired — each against its own trip so they
  // don't interfere (this driver is the only eligible one for each).
  for (let i = 0; i < 2; i++) {
    const rider = await newRider(`accept-${i}`);
    const trip = await prisma.trip.create({
      data: { riderId: rider.id, pickup: "A", destination: "B", estimatedFare: 10, status: "REQUESTED" },
    });
    const offer = await prisma.tripOffer.create({
      data: { tripId: trip.id, driverId, expiresAt: new Date(Date.now() + 60_000) },
    });
    const res = await request(app)
      .patch(`/api/trip-offers/${offer.id}/accept`)
      .set("Authorization", `Bearer ${mockAuthAs({ sub: "e2e-rate-driver-1", groups: ["Driver"] })}`);
    assert.equal(res.status, 200);

    // Free the driver (a busy driver can't hold two active assignments) so
    // the next iteration's accept isn't rejected as a real double-booking.
    const driverTokenForComplete = mockAuthAs({ sub: "e2e-rate-driver-1", groups: ["Driver"] });
    await request(app)
      .patch(`/api/trips/${trip.id}/status`)
      .set("Authorization", `Bearer ${driverTokenForComplete}`)
      .send({ status: "IN_PROGRESS" });
    await request(app)
      .patch(`/api/trips/${trip.id}/status`)
      .set("Authorization", `Bearer ${driverTokenForComplete}`)
      .send({ status: "COMPLETED", finalFare: 10 });
  }

  const declineRider = await newRider("decline");
  const declineTrip = await prisma.trip.create({
    data: { riderId: declineRider.id, pickup: "A", destination: "B", estimatedFare: 10, status: "REQUESTED" },
  });
  const declineOffer = await prisma.tripOffer.create({
    data: { tripId: declineTrip.id, driverId, expiresAt: new Date(Date.now() + 60_000) },
  });
  const declineRes = await request(app)
    .patch(`/api/trip-offers/${declineOffer.id}/decline`)
    .set("Authorization", `Bearer ${mockAuthAs({ sub: "e2e-rate-driver-1", groups: ["Driver"] })}`);
  assert.equal(declineRes.status, 200);

  const expireRider = await newRider("expire");
  const expireTrip = await prisma.trip.create({
    data: { riderId: expireRider.id, pickup: "A", destination: "B", estimatedFare: 10, status: "REQUESTED" },
  });
  await prisma.tripOffer.create({
    data: { tripId: expireTrip.id, driverId, status: "EXPIRED", respondedAt: new Date(), expiresAt: new Date(Date.now() - 1000) },
  });

  const after = await request(app)
    .get("/api/drivers/me")
    .set("Authorization", `Bearer ${mockAuthAs({ sub: "e2e-rate-driver-1", groups: ["Driver"] })}`);
  // 2 accepted / 4 total (accepted+declined+expired) = 50%.
  assert.deepEqual(after.body.acceptanceStats, {
    totalOffers: 4,
    acceptedOffers: 2,
    declinedOffers: 1,
    expiredOffers: 1,
    acceptanceRate: 0.5,
  });
});

test("Concurrency: a double-tap Accept on the same offer — exactly one succeeds, the trip is never corrupted", async () => {
  const driverToken = mockAuthAs({ sub: "e2e-dbltap-driver-1", groups: ["Driver"] });
  const driverProfile = await request(app)
    .post("/api/drivers/me")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ firstName: "Double", lastName: "Tap", email: "double.tap@example.com" });
  await prisma.driver.update({ where: { id: driverProfile.body.id }, data: { status: "ACTIVE", online: true } });

  const riderToken = mockAuthAs({ sub: "e2e-dbltap-rider-1", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ firstName: "Rider", lastName: "One", email: "rider.dbltap@example.com" });
  const requested = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ pickup: "A", destination: "B", estimatedFare: 1000 });
  const tripId = requested.body.id as string;

  const driverTokenAgain = "mock.e2e-dbltap-driver-1";
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate === driverTokenAgain) return { sub: "e2e-dbltap-driver-1", "cognito:groups": ["Driver"] } as never;
    throw new Error("invalid token");
  });
  const offer = await prisma.tripOffer.findFirstOrThrow({ where: { tripId } });

  const [first, second] = await Promise.all([
    request(app).patch(`/api/trip-offers/${offer.id}/accept`).set("Authorization", `Bearer ${driverTokenAgain}`),
    request(app).patch(`/api/trip-offers/${offer.id}/accept`).set("Authorization", `Bearer ${driverTokenAgain}`),
  ]);

  const statuses = [first.status, second.status].sort();
  assert.deepEqual(statuses, [200, 409]);

  const finalTrip = await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  assert.equal(finalTrip.status, "MATCHED");
  assert.equal(finalTrip.driverId, driverProfile.body.id);

  const activeAssignments = await prisma.driverAssignment.findMany({
    where: { driverId: driverProfile.body.id, status: "ACTIVE" },
  });
  assert.equal(activeAssignments.length, 1, "a double-tap accept must never create two assignments");
});
