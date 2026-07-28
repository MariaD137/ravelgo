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

test("POST /api/trips lets a Rider request a trip", async () => {
  await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "REQUESTED");
});

test("POST /api/trips rejects a Driver caller", async () => {
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
  const res = await request(app)
    .post("/api/trips")
    .set("Authorization", `Bearer ${token}`)
    .send({ pickup: "Home", destination: "Airport", estimatedFare: 25.5 });
  assert.equal(res.status, 403);
});

test("GET /api/trips/:id allows the rider who owns it, denies a stranger", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-2", role: "RIDER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12 },
  });

  const ownerToken = mockAuthAs({ sub: "rider-sub-2", groups: ["Rider"] });
  const ownerRes = await request(app).get(`/api/trips/${trip.id}`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownerRes.status, 200);

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "rider-sub-3", groups: ["Rider"] });
  const strangerRes = await request(app).get(`/api/trips/${trip.id}`).set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 403);
});

test("PATCH /api/trips/:id/status lets a Driver or Admin advance trip status", async () => {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-4", role: "RIDER", firstName: "E", lastName: "F", email: "e@example.com" },
  });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, pickup: "X", destination: "Y", estimatedFare: 12, status: "MATCHED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/trips/${trip.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "COMPLETED", finalFare: 14 });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "COMPLETED");
  assert.ok(res.body.completedAt);
});

test("GET /api/trips (Admin monitor) rejects a Rider caller", async () => {
  const token = mockAuthAs({ sub: "rider-sub-5", groups: ["Rider"] });
  const res = await request(app).get("/api/trips").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});
