import assert from "node:assert/strict";
import { after, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import * as pricingService from "../services/pricing";

after(async () => {
  await prisma.$disconnect();
});

test("GET /health reports ok when the database is reachable", async () => {
  const res = await request(app).get("/health");
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "ok");
  assert.equal(res.body.database, "connected");
});

test("GET /health/pricing reports pricing-table row counts without auth (and without any rate or PII)", async () => {
  const res = await request(app).get("/health/pricing");
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "ok");
  assert.equal(typeof res.body.rideCategories.total, "number");
  assert.equal(typeof res.body.rideCategories.active, "number");
  assert.equal(typeof res.body.activePricingRules, "number");
  assert.equal(typeof res.body.commissionConfigRows, "number");
  // Counts only — never a rate card, key, or per-user detail.
  assert.doesNotMatch(JSON.stringify(res.body), /baseFare|perKm|secret|email/i);
});

test("GET /health/pricing surfaces a database failure as 503 with the error code instead of swallowing it", async (t) => {
  const missingTable = Object.assign(new Error('The table `public.RideCategory` does not exist'), {
    name: "PrismaClientKnownRequestError",
    code: "P2021",
  });
  t.mock.method(pricingService, "pricingDiagnostics", () => Promise.reject(missingTable));
  const res = await request(app).get("/health/pricing");
  assert.equal(res.status, 503);
  assert.equal(res.body.status, "error");
  assert.equal(res.body.error.code, "P2021");
  assert.match(res.body.error.hint, /migrate/);
  // The raw table name stays in the server log, not the response.
  assert.doesNotMatch(JSON.stringify(res.body), /public\.RideCategory/);
});

/**
 * /health/schema is the probe that would have caught the Rent-a-Car outage:
 * the deploy went fully green while every Driver-backed query returned
 * "Database schema is out of date on this server", because no other probe
 * touches those tables.
 */
test("GET /health/schema reports the migration state, unauthenticated and without leaking anything", async () => {
  const res = await request(app).get("/health/schema");

  assert.equal(res.status, 200, "the test database is fully migrated");
  assert.equal(res.body.status, "ok");
  assert.deepEqual(res.body.pending, []);
  assert.deepEqual(res.body.failed, []);
  assert.equal(res.body.expected, res.body.applied);
  assert.ok(res.body.expected > 0, "it really counted the migrations shipped on disk");

  // Diagnostics only: no rows, no credentials, no connection details.
  const blob = JSON.stringify(res.body);
  assert.ok(!blob.includes("postgres"), "must not leak connection details");
  assert.ok(!blob.includes("password"));
});
