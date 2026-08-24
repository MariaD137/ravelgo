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
    .send({ bucket: "documents", fileName: "license.pdf", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 403);
});

test("POST /api/uploads/presign returns a signed URL scoped to the caller", async () => {
  const token = mockAuthAs({ sub: "user-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "license.pdf", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 200);
  assert.match(res.body.uploadUrl, /^https:\/\//);
  assert.match(res.body.fileKey, /^user-sub-1\//);
  assert.equal(res.body.expiresIn, 300);
});

test("POST /api/uploads/presign rejects an invalid bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "not-a-real-bucket", fileName: "x.pdf", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects an unsupported content type for the bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "malware.exe", contentType: "application/x-msdownload", fileSize: 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects an HTML file even with a spoofed image extension", async () => {
  const token = mockAuthAs({ sub: "user-sub-4", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    // Filename extension alone must not decide validity — contentType does.
    .send({ bucket: "assets", fileName: "photo.jpg", contentType: "text/html", fileSize: 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a file over the per-bucket size limit", async () => {
  const token = mockAuthAs({ sub: "user-sub-5", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "huge.jpg", contentType: "image/jpeg", fileSize: 50 * 1024 * 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign allows an Admin caller too", async () => {
  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "note.pdf", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 200);
});
