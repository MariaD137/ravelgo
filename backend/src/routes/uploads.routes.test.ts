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
    .send({ bucket: "documents", fileName: "license.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 200);
  assert.match(res.body.url, /^https:\/\//);
  assert.equal(typeof res.body.fields, "object");
  assert.equal(res.body.fields.key, res.body.fileKey);
  assert.match(res.body.fileKey, /^user-sub-1\//);
  assert.equal(res.body.expiresIn, 300);
  assert.equal(res.body.maxUploadBytes, 15 * 1024 * 1024);
});

test("POST /api/uploads/presign sanitizes a path-traversal filename", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "../../etc/passwd", contentType: "application/pdf" });

  assert.equal(res.status, 200);
  assert.doesNotMatch(res.body.fileKey, /\.\./);
  assert.doesNotMatch(res.body.fileKey, /etc\/passwd/);
});

test("POST /api/uploads/presign rejects an invalid bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "not-a-real-bucket", fileName: "x.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});
