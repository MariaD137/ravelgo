import assert from "node:assert/strict";
import { test } from "node:test";
import request from "supertest";
import { app } from "../app";

test("malformed JSON body is reported as 400, not 500 (body-parser's own error is exposed, not swallowed into a generic 500)", async () => {
  const res = await request(app)
    .post("/api/riders/me")
    .set("Content-Type", "application/json")
    .send("{not valid json");

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, "BAD_REQUEST");
  // Never echo the raw parse error / request bytes back to the client.
  assert.doesNotMatch(res.body.error.message, /not valid json/);
});

test("error responses never include a stack trace, regardless of status", async () => {
  const res = await request(app).get("/api/does-not-exist-at-all");
  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, "NOT_FOUND");
  assert.ok(!("stack" in res.body.error));
});
