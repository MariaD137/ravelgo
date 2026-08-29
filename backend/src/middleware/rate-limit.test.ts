import assert from "node:assert/strict";
import { test } from "node:test";
import express from "express";
import request from "supertest";
import { createRateLimiter } from "./rate-limit";

// Build a throwaway app whose limiter actually enforces (skip disabled), so
// we can prove both halves of the requirement without polluting the shared
// app's limiter state: an attacker eventually gets 429, and traffic under the
// limit keeps working.
function appWithLimit(limit: number) {
  const app = express();
  app.use(createRateLimiter({ limit, name: "test", skip: () => false }));
  app.get("/ping", (_req, res) => res.json({ ok: true }));
  return app;
}

test("requests under the limit all succeed", async () => {
  const app = appWithLimit(3);
  for (let i = 0; i < 3; i++) {
    const res = await request(app).get("/ping");
    assert.equal(res.status, 200);
  }
});

test("the request over the limit is rejected with a 429 and a structured body", async () => {
  const app = appWithLimit(2);
  await request(app).get("/ping");
  await request(app).get("/ping");

  const blocked = await request(app).get("/ping");
  assert.equal(blocked.status, 429);
  assert.equal(blocked.body.error.code, "RATE_LIMIT_EXCEEDED");
  assert.match(blocked.body.error.message, /too many requests/i);
});
