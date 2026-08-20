import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { mockAuthAs, restoreAuth } from "../test/helpers";

afterEach(() => {
  restoreAuth();
});

test("POST /api/uploads/presign requires auth", async () => {
  const res = await request(app).post("/api/uploads/presign").send({});
  assert.equal(res.status, 401);
});

test("POST /api/uploads/presign returns a signed POST policy scoped to the caller, for documents", async () => {
  const token = mockAuthAs({ sub: "user-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "license.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 200);
  assert.match(res.body.url, /^https:\/\//);
  assert.match(res.body.fileKey, /^user-sub-1\//);
  assert.match(res.body.fileKey, /license\.pdf$/);
  assert.ok(res.body.fields);
  assert.equal(res.body.expiresIn, 300);
});

// "assets" uploads must land in PENDING_ASSETS_BUCKET, never directly in
// the CloudFront-served AssetsBucket — see uploads.routes.ts and
// docs/UPLOAD-VALIDATION.md. This is the one thing this test actually
// needs to prove: that an "assets" presign targets the staging bucket and
// not the public one.
test("POST /api/uploads/presign routes assets uploads to the pending bucket, not the public one", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "avatar.jpg", contentType: "image/jpeg" });

  assert.equal(res.status, 200);
  assert.match(res.body.url, new RegExp(`^https://${process.env.PENDING_ASSETS_BUCKET}\\.`));
});

test("POST /api/uploads/presign rejects an invalid bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "not-a-real-bucket", fileName: "x.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign strips path separators from fileName so it can't escape the caller's key prefix", async () => {
  const token = mockAuthAs({ sub: "user-sub-4", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "../../etc/passwd", contentType: "application/pdf" });

  assert.equal(res.status, 200);
  assert.match(res.body.fileKey, /^user-sub-4\/[0-9a-f-]+-passwd$/);
});

test("POST /api/uploads/presign rejects a fileName that sanitizes to nothing", async () => {
  const token = mockAuthAs({ sub: "user-sub-5", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    // A trailing "/" is the one input sanitizeFileName's own splitting logic
    // reduces to an empty string, rather than just replacing characters —
    // "***" would sanitize to "___", which is truthy and not what this test
    // means to exercise.
    .send({ bucket: "documents", fileName: "/", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});
