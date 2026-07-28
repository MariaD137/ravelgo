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
  assert.match(res.body.uploadUrl, /^https:\/\//);
  assert.match(res.body.fileKey, /^user-sub-1\//);
  assert.equal(res.body.expiresIn, 300);
});

test("POST /api/uploads/presign rejects an invalid bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-2", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "not-a-real-bucket", fileName: "x.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});
