import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, resetDb, restoreAuth } from "../test/helpers";
import { SETTINGS_ID } from "../lib/payment-rules";
import { generateReferralCode, normalizeReferralCode } from "../lib/referral-rules";
import { maybeRewardReferral } from "../services/referral";

/**
 * The referral programme moves real money into real wallets, so these tests
 * are mostly about the ways it must REFUSE to: self-referral, double claims,
 * established accounts backdating themselves, and above all paying twice.
 */

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
async function seedRider(sub: string) {
  seq += 1;
  return prisma.user.create({
    data: { cognitoSub: sub, role: "RIDER", firstName: "R", lastName: `${seq}`, email: `${sub}@example.com` },
  });
}

async function enableProgram(overrides: Record<string, unknown> = {}) {
  return prisma.appSetting.upsert({
    where: { id: SETTINGS_ID },
    update: { referralEnabled: true, ...overrides },
    create: { id: SETTINGS_ID, referralEnabled: true, ...overrides },
  });
}

/** A COMPLETED trip for this rider, which is what qualifies a referral. */
async function completeTrip(riderId: string) {
  return prisma.trip.create({
    data: {
      riderId,
      pickup: "A",
      destination: "B",
      estimatedFare: 1000,
      finalFare: 1000,
      status: "COMPLETED",
      completedAt: new Date(),
    },
  });
}

async function codeFor(sub: string): Promise<string> {
  const token = mockAuthAs({ sub, groups: ["Rider"] });
  const res = await request(app).get("/api/riders/me/referral").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  restoreAuth();
  return res.body.code as string;
}

async function balanceOf(userId: string): Promise<number> {
  const wallet = await prisma.walletAccount.findUnique({ where: { userId } });
  return wallet?.balanceCents ?? 0;
}

// --- code issuance --------------------------------------------------------

test("GET /api/riders/me/referral issues a code once and keeps returning the same one", async () => {
  await seedRider("ref-owner-1");
  await enableProgram();
  const token = mockAuthAs({ sub: "ref-owner-1", groups: ["Rider"] });

  const first = await request(app).get("/api/riders/me/referral").set("Authorization", `Bearer ${token}`);
  assert.equal(first.status, 200);
  assert.match(first.body.code, /^[A-Z0-9]{8}$/);
  assert.equal(first.body.pending, 0);
  assert.equal(first.body.rewarded, 0);
  assert.equal(first.body.totalEarned, 0);
  assert.equal(first.body.program.enabled, true);

  const second = await request(app).get("/api/riders/me/referral").set("Authorization", `Bearer ${token}`);
  assert.equal(second.body.code, first.body.code, "a rider's code must be stable");
});

test("referral codes avoid characters that are ambiguous when retyped", () => {
  for (let i = 0; i < 200; i += 1) {
    assert.doesNotMatch(generateReferralCode(), /[01OIL]/);
  }
  assert.equal(normalizeReferralCode("  abc123  "), "ABC123");
});

test("GET /api/riders/me/referral rejects a non-rider", async () => {
  const token = mockAuthAs({ sub: "ref-driver-1", groups: ["Driver"] });
  const res = await request(app).get("/api/riders/me/referral").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

// --- claiming -------------------------------------------------------------

test("a new rider can claim someone else's code, once", async () => {
  const referrer = await seedRider("ref-a-1");
  await seedRider("ref-b-1");
  await enableProgram();
  const code = await codeFor("ref-a-1");

  const token = mockAuthAs({ sub: "ref-b-1", groups: ["Rider"] });
  const claim = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code: code.toLowerCase() }); // case-insensitive on purpose
  assert.equal(claim.status, 201);
  assert.equal(claim.body.referrerId, referrer.id);
  assert.equal(claim.body.status, "PENDING");

  // A second claim is refused, and never creates a second row.
  const again = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  assert.equal(again.status, 409);
  assert.equal(await prisma.referral.count(), 1);
});

test("a rider cannot refer themselves", async () => {
  await seedRider("ref-self-1");
  await enableProgram();
  const code = await codeFor("ref-self-1");

  const token = mockAuthAs({ sub: "ref-self-1", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  assert.equal(res.status, 400);
  assert.equal(await prisma.referral.count(), 0);
});

test("an established rider cannot backdate themselves into a referral", async () => {
  await seedRider("ref-a-2");
  const referee = await seedRider("ref-b-2");
  await enableProgram();
  const code = await codeFor("ref-a-2");
  // This rider has already ridden — the programme is for NEW riders.
  await completeTrip(referee.id);

  const token = mockAuthAs({ sub: "ref-b-2", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  assert.equal(res.status, 409);
  assert.equal(await prisma.referral.count(), 0);
});

test("an unknown code is refused, and so is a deleted referrer's code", async () => {
  const referrer = await seedRider("ref-a-3");
  await seedRider("ref-b-3");
  await enableProgram();
  const code = await codeFor("ref-a-3");

  const token = mockAuthAs({ sub: "ref-b-3", groups: ["Rider"] });
  const unknown = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code: "ZZZZZZZZ" });
  assert.equal(unknown.status, 404);

  // A soft-deleted rider's code stops earning.
  await prisma.user.update({ where: { id: referrer.id }, data: { deletedAt: new Date() } });
  const deleted = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  assert.equal(deleted.status, 404);
  assert.equal(await prisma.referral.count(), 0);
});

test("no claim is accepted while the programme is switched off", async () => {
  await seedRider("ref-a-4");
  await seedRider("ref-b-4");
  await enableProgram();
  const code = await codeFor("ref-a-4");
  await prisma.appSetting.update({ where: { id: SETTINGS_ID }, data: { referralEnabled: false } });

  const token = mockAuthAs({ sub: "ref-b-4", groups: ["Rider"] });
  const res = await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  assert.equal(res.status, 409);
  assert.equal(await prisma.referral.count(), 0, "a disabled programme must not accumulate a payout backlog");
});

// --- qualifying and paying ------------------------------------------------

test("the referrer is paid once the referee completes the qualifying trips", async () => {
  const referrer = await seedRider("ref-a-5");
  const referee = await seedRider("ref-b-5");
  await enableProgram({ referralRewardAmount: 1500, referralQualifyingTrips: 2 });
  const code = await codeFor("ref-a-5");

  const token = mockAuthAs({ sub: "ref-b-5", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  restoreAuth();

  // One trip is not enough when the programme asks for two.
  await completeTrip(referee.id);
  await maybeRewardReferral(referee.id);
  assert.equal((await prisma.referral.findFirstOrThrow()).status, "PENDING");
  assert.equal(await balanceOf(referrer.id), 0);

  await completeTrip(referee.id);
  await maybeRewardReferral(referee.id);

  const settled = await prisma.referral.findFirstOrThrow();
  assert.equal(settled.status, "REWARDED");
  assert.equal(settled.referrerRewardAmount, 1500);
  assert.ok(settled.rewardedAt);
  assert.equal(await balanceOf(referrer.id), 150_000, "1500 NGN in cents");

  const ledger = await prisma.walletTransaction.findMany({ where: { type: "REFERRAL_BONUS" } });
  assert.equal(ledger.length, 1);
  assert.equal(ledger[0].amountCents, 150_000);

  const notifications = await prisma.notification.findMany({ where: { userId: referrer.id } });
  assert.ok(notifications.some((n) => n.type === "REFERRAL_REWARDED"));
});

test("a referral is never paid twice, however many times settlement runs", async () => {
  const referrer = await seedRider("ref-a-6");
  const referee = await seedRider("ref-b-6");
  await enableProgram({ referralRewardAmount: 1000, referralQualifyingTrips: 1 });
  const code = await codeFor("ref-a-6");

  const token = mockAuthAs({ sub: "ref-b-6", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  restoreAuth();
  await completeTrip(referee.id);

  // Sequential retries and a concurrent burst both settle exactly once.
  await maybeRewardReferral(referee.id);
  await maybeRewardReferral(referee.id);
  await Promise.all([
    maybeRewardReferral(referee.id),
    maybeRewardReferral(referee.id),
    maybeRewardReferral(referee.id),
  ]);

  assert.equal(await balanceOf(referrer.id), 100_000, "paid exactly once");
  assert.equal(await prisma.walletTransaction.count({ where: { type: "REFERRAL_BONUS" } }), 1);
  assert.equal(await prisma.referral.count({ where: { status: "REWARDED" } }), 1);
});

test("both sides are credited when the programme rewards the new rider too", async () => {
  const referrer = await seedRider("ref-a-7");
  const referee = await seedRider("ref-b-7");
  await enableProgram({ referralRewardAmount: 1000, referralRefereeRewardAmount: 500 });
  const code = await codeFor("ref-a-7");

  const token = mockAuthAs({ sub: "ref-b-7", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  restoreAuth();
  await completeTrip(referee.id);
  await maybeRewardReferral(referee.id);

  assert.equal(await balanceOf(referrer.id), 100_000);
  assert.equal(await balanceOf(referee.id), 50_000);
  assert.equal(await prisma.walletTransaction.count({ where: { type: "REFERRAL_BONUS" } }), 2);
});

test("a zero referee reward leaves no empty wallet row for the new rider", async () => {
  const referrer = await seedRider("ref-a-8");
  const referee = await seedRider("ref-b-8");
  await enableProgram({ referralRewardAmount: 1000, referralRefereeRewardAmount: 0 });
  const code = await codeFor("ref-a-8");

  const token = mockAuthAs({ sub: "ref-b-8", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  restoreAuth();
  await completeTrip(referee.id);
  await maybeRewardReferral(referee.id);

  assert.equal(await balanceOf(referrer.id), 100_000);
  assert.equal(await prisma.walletTransaction.count({ where: { type: "REFERRAL_BONUS" } }), 1);
});

test("switching the programme off stops pending referrals paying out", async () => {
  const referrer = await seedRider("ref-a-9");
  const referee = await seedRider("ref-b-9");
  await enableProgram();
  const code = await codeFor("ref-a-9");

  const token = mockAuthAs({ sub: "ref-b-9", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${token}`)
    .send({ code });
  restoreAuth();
  await prisma.appSetting.update({ where: { id: SETTINGS_ID }, data: { referralEnabled: false } });

  await completeTrip(referee.id);
  await maybeRewardReferral(referee.id);

  assert.equal((await prisma.referral.findFirstOrThrow()).status, "PENDING");
  assert.equal(await balanceOf(referrer.id), 0);
});

test("completing a trip settles the referral through the real endpoint", async () => {
  const referrer = await seedRider("ref-a-10");
  const referee = await seedRider("ref-b-10");
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "ref-drv-10", role: "DRIVER", firstName: "D", lastName: "R", email: "refdrv@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  await enableProgram({ referralRewardAmount: 800, referralQualifyingTrips: 1 });
  const code = await codeFor("ref-a-10");

  const riderToken = mockAuthAs({ sub: "ref-b-10", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ code });
  restoreAuth();

  const trip = await prisma.trip.create({
    data: {
      riderId: referee.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 1200,
      status: "IN_PROGRESS",
    },
  });
  const driverToken = mockAuthAs({ sub: "ref-drv-10", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ status: "COMPLETED", finalFare: 1200 });
  assert.equal(res.status, 200);

  assert.equal((await prisma.referral.findFirstOrThrow()).status, "REWARDED");
  assert.equal(await balanceOf(referrer.id), 80_000);
});

// --- admin ----------------------------------------------------------------

test("an admin can configure the programme, and every change is audited", async () => {
  const token = mockAuthAs({ sub: "ref-admin-1", groups: ["Admin"] });
  const res = await request(app)
    .patch("/api/admin/settings/referral")
    .set("Authorization", `Bearer ${token}`)
    .send({ referralEnabled: true, referralRewardAmount: 2500, referralQualifyingTrips: 3 });

  assert.equal(res.status, 200);
  assert.equal(res.body.enabled, true);
  assert.equal(res.body.rewardAmount, 2500);
  assert.equal(res.body.qualifyingTrips, 3);

  const audits = await prisma.auditLog.findMany({ where: { action: "REFERRAL_SETTING_CHANGED" } });
  assert.equal(audits.length, 3, "one row per field actually changed");

  // A no-op change writes no audit row.
  await request(app)
    .patch("/api/admin/settings/referral")
    .set("Authorization", `Bearer ${token}`)
    .send({ referralRewardAmount: 2500 });
  assert.equal(await prisma.auditLog.count({ where: { action: "REFERRAL_SETTING_CHANGED" } }), 3);
});

test("the programme rejects nonsense values and non-admin callers", async () => {
  const adminToken = mockAuthAs({ sub: "ref-admin-2", groups: ["Admin"] });
  for (const body of [
    { referralRewardAmount: -1 },
    { referralQualifyingTrips: 0 },
    {},
  ]) {
    const res = await request(app)
      .patch("/api/admin/settings/referral")
      .set("Authorization", `Bearer ${adminToken}`)
      .send(body);
    assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(body)}`);
  }
  restoreAuth();

  const riderToken = mockAuthAs({ sub: "ref-rider-2", groups: ["Rider"] });
  const refused = await request(app)
    .patch("/api/admin/settings/referral")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ referralEnabled: true });
  assert.equal(refused.status, 403);
});

test("GET /api/admin/referrals lists and filters referrals for an admin only", async () => {
  await seedRider("ref-a-11");
  await seedRider("ref-b-11");
  await enableProgram();
  const code = await codeFor("ref-a-11");
  const riderToken = mockAuthAs({ sub: "ref-b-11", groups: ["Rider"] });
  await request(app)
    .post("/api/riders/me/referral/claim")
    .set("Authorization", `Bearer ${riderToken}`)
    .send({ code });

  const refused = await request(app).get("/api/admin/referrals").set("Authorization", `Bearer ${riderToken}`);
  assert.equal(refused.status, 403);
  restoreAuth();

  const adminToken = mockAuthAs({ sub: "ref-admin-3", groups: ["Admin"] });
  const res = await request(app).get("/api/admin/referrals").set("Authorization", `Bearer ${adminToken}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.total, 1);
  assert.equal(res.body.data[0].status, "PENDING");
  assert.ok(res.body.data[0].referrer.email, "the admin list carries both parties");
  assert.ok(res.body.data[0].referee.email);

  const rewardedOnly = await request(app)
    .get("/api/admin/referrals?status=REWARDED")
    .set("Authorization", `Bearer ${adminToken}`);
  assert.equal(rewardedOnly.body.total, 0);
});
