import assert from "node:assert/strict";
import { test } from "node:test";
import express from "express";
import { rateLimit } from "express-rate-limit";
import request from "supertest";
import { app } from "../app";

test("app.ts sets trust proxy to 1 for AWS App Runner's single-hop proxy", () => {
  // Behind App Runner, the container sees every request as one hop removed
  // from the real client (X-Forwarded-For is set by that one hop). Without
  // this, express-rate-limit below would key its whole budget off App
  // Runner's own address instead of per real caller — see app.ts's comment.
  assert.equal(app.get("trust proxy"), 1);
});

// Exercises express-rate-limit + trust-proxy the same way app.ts wires them,
// against a minimal standalone app (the real app disables rate limiting in
// NODE_ENV=test — see app.ts — so this isolates just that interaction).
function buildRateLimitedApp(trustProxy: number | boolean | undefined) {
  const testApp = express();
  if (trustProxy !== undefined) testApp.set("trust proxy", trustProxy);
  testApp.use(rateLimit({ windowMs: 60_000, limit: 2, standardHeaders: true, legacyHeaders: false }));
  testApp.get("/ping", (_req, res) => res.json({ ok: true }));
  return testApp;
}

test("with trust proxy set (App Runner's config), each X-Forwarded-For client gets its own rate-limit budget", async () => {
  const testApp = buildRateLimitedApp(1);

  await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.10").expect(200);
  await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.10").expect(200);
  const thirdFromA = await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.10");
  assert.equal(thirdFromA.status, 429);

  // A different real client, forwarded through the same proxy, is unaffected.
  const firstFromB = await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.20");
  assert.equal(firstFromB.status, 200);
});

test("without trust proxy set, distinct X-Forwarded-For clients collapse into one shared rate-limit budget", async () => {
  const testApp = buildRateLimitedApp(undefined);

  // supertest connects over loopback, so with trust proxy off, req.ip is the
  // loopback socket address for every request regardless of the (untrusted)
  // X-Forwarded-For header — this reproduces the bug the trust-proxy fix
  // closes: two different callers exhausting one shared budget.
  await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.10").expect(200);
  await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.20").expect(200);
  const third = await request(testApp).get("/ping").set("X-Forwarded-For", "203.0.113.30");
  assert.equal(third.status, 429);
});
