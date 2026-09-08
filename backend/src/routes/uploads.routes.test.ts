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

test("POST /api/uploads/presign rejects a content type that could execute in a browser", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Driver"] });

  for (const contentType of ["text/html", "image/svg+xml", "application/javascript"]) {
    const res = await request(app)
      .post("/api/uploads/presign")
      .set("Authorization", `Bearer ${token}`)
      .send({ bucket: "assets", fileName: "x", contentType, fileSize: 1024 });
    assert.equal(res.status, 400, `expected ${contentType} to be rejected`);
  }
});

test("POST /api/uploads/presign rejects a PDF for the publicly-served assets bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-4", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "x.pdf", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a fileName containing a path separator", async () => {
  const token = mockAuthAs({ sub: "user-sub-5", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "../../etc/passwd", contentType: "application/pdf", fileSize: 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a fileSize over the bucket's real limit", async () => {
  const token = mockAuthAs({ sub: "user-sub-6", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "huge.pdf", contentType: "application/pdf", fileSize: 20 * 1024 * 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a fileSize over the assets bucket's (smaller) limit", async () => {
  const token = mockAuthAs({ sub: "user-sub-7", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "huge.jpg", contentType: "image/jpeg", fileSize: 9 * 1024 * 1024 });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a missing fileSize", async () => {
  const token = mockAuthAs({ sub: "user-sub-8", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "x.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});
