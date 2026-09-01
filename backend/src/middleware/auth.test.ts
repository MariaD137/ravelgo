import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import express from "express";
import request from "supertest";
import { requireAuth, requireRole } from "./auth";
import { mockAuthAs, restoreAuth } from "../test/helpers";

// A throwaway app exercising the auth middleware in isolation, so the tests
// document exactly where the "bot"/unauthenticated boundary sits: no route
// body runs until requireAuth has verified a real Cognito access token, and
// requireRole gates by Cognito group on top of that.
function protectedApp() {
  const app = express();
  app.get("/me", requireAuth, (req, res) => res.json({ sub: req.user!.sub, groups: req.user!.groups }));
  app.get("/admin", requireAuth, requireRole("Admin"), (_req, res) => res.json({ ok: true }));
  return app;
}

afterEach(() => restoreAuth());

test("a request with no Authorization header is rejected 401 (anonymous bot)", async () => {
  const res = await request(protectedApp()).get("/me");
  assert.equal(res.status, 401);
});

test("a non-Bearer Authorization header is rejected 401", async () => {
  const res = await request(protectedApp()).get("/me").set("Authorization", "Basic abc123");
  assert.equal(res.status, 401);
});

test("a token that fails Cognito verification is rejected 401", async () => {
  // Install a verifier that only accepts the real token, then send a different
  // one so verify() throws — no network call, deterministic.
  mockAuthAs({ sub: "user-1", groups: ["Rider"] });
  const res = await request(protectedApp()).get("/me").set("Authorization", "Bearer forged.token");
  assert.equal(res.status, 401);
});

test("a valid access token passes requireAuth and populates req.user", async () => {
  const token = mockAuthAs({ sub: "user-1", groups: ["Rider"] });
  const res = await request(protectedApp()).get("/me").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.sub, "user-1");
  assert.deepEqual(res.body.groups, ["Rider"]);
});

test("requireRole rejects an authenticated user who lacks the group (403, not 401)", async () => {
  const token = mockAuthAs({ sub: "user-1", groups: ["Rider"] });
  const res = await request(protectedApp()).get("/admin").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("requireRole admits a user in the required group", async () => {
  const token = mockAuthAs({ sub: "admin-1", groups: ["Admin"] });
  const res = await request(protectedApp()).get("/admin").set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 200);
});
