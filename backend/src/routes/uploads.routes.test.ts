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

test("POST /api/uploads/presign rejects a Rider caller (Driver/Admin only)", async () => {
  const token = mockAuthAs({ sub: "rider-sub-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "license.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 403);
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
  assert.equal(res.body.maxBytes, 10 * 1024 * 1024);
});

// Regression test: ALLOWED_CONTENT_TYPES's "documents" list must include
// image/heic — a driver's license photo shot on an iPhone is exactly as
// plausible as a HEIC vehicle photo — or the infra/lambda/upload-processor
// allowlist for DOCUMENTS_BUCKET has to reject it moments later, silently
// deleting an upload that presigned successfully. This only proves the
// presign side; the Lambda side isn't exercised by these tests (it runs on
// AWS, not in this Express app), so keeping the two allowlists in sync is a
// manual invariant across this file and
// infra/lambda/upload-processor/index.ts's ALLOWED_MIME_BY_BUCKET.
test("POST /api/uploads/presign accepts a HEIC document, not just images/PDF headed to assets", async () => {
  const token = mockAuthAs({ sub: "user-sub-6", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "license.heic", contentType: "image/heic" });

  assert.equal(res.status, 200);
  assert.match(res.body.fileKey, /license\.heic$/);
});

// "assets" uploads must land in PENDING_ASSETS_BUCKET, never directly in
// the CloudFront-served AssetsBucket — see uploads.routes.ts and
// infra/lambda/upload-processor/index.ts. This is the one thing this test
// actually needs to prove: that an "assets" presign targets the staging
// bucket and not the public one.
test("POST /api/uploads/presign routes assets uploads to the pending bucket, not the public one", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "car-front.jpg", contentType: "image/jpeg" });

  assert.equal(res.status, 200);
  assert.match(res.body.url, new RegExp(`^https://${process.env.PENDING_ASSETS_BUCKET}\\.`));
  assert.equal(res.body.maxBytes, 8 * 1024 * 1024);
});

test("POST /api/uploads/presign rejects an invalid bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "not-a-real-bucket", fileName: "x.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects an unsupported content type for the bucket (PDF headed to assets)", async () => {
  const token = mockAuthAs({ sub: "user-sub-3b", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "doc.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects an HTML file even with a spoofed image extension", async () => {
  const token = mockAuthAs({ sub: "user-sub-4", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    // Filename extension alone must not decide validity — contentType does.
    .send({ bucket: "assets", fileName: "photo.jpg", contentType: "text/html" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign strips path separators from fileName so it can't escape the caller's key prefix", async () => {
  const token = mockAuthAs({ sub: "user-sub-4b", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "../../etc/passwd", contentType: "application/pdf" });

  assert.equal(res.status, 200);
  assert.match(res.body.fileKey, /^user-sub-4b\/[0-9a-f-]+-passwd$/);
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

test("POST /api/uploads/presign allows an Admin caller too", async () => {
  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "note.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 200);
});
