import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { mockAuthAs, mockPresignedUrl, restoreAuth } from "../test/helpers";

afterEach(() => {
  restoreAuth();
});

test("POST /api/uploads/presign requires auth", async () => {
  const res = await request(app).post("/api/uploads/presign").send({});
  assert.equal(res.status, 401);
});

test("POST /api/uploads/presign returns a signed URL scoped to the caller", async () => {
  const token = mockAuthAs({ sub: "user-sub-1", groups: ["Driver"] });
  mockPresignedUrl();

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

test("POST /api/uploads/presign rejects text/html contentType (stored-XSS-via-asset prevention)", async () => {
  const token = mockAuthAs({ sub: "user-sub-3", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "avatar.png", contentType: "text/html" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects image/svg+xml (can embed <script>)", async () => {
  const token = mockAuthAs({ sub: "user-sub-4", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "avatar.svg", contentType: "image/svg+xml" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects a PDF contentType against the assets bucket (images only)", async () => {
  const token = mockAuthAs({ sub: "user-sub-5", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "doc.pdf", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign accepts an allowed image contentType against the assets bucket", async () => {
  const token = mockAuthAs({ sub: "user-sub-6", groups: ["Driver"] });
  mockPresignedUrl();

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "assets", fileName: "car.jpg", contentType: "image/jpeg" });

  assert.equal(res.status, 200);
});

test("POST /api/uploads/presign rejects a fileName with path/control characters", async () => {
  const token = mockAuthAs({ sub: "user-sub-7", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: "../../etc/passwd", contentType: "application/pdf" });

  assert.equal(res.status, 400);
});

test("POST /api/uploads/presign rejects an overlong fileName", async () => {
  const token = mockAuthAs({ sub: "user-sub-8", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/uploads/presign")
    .set("Authorization", `Bearer ${token}`)
    .send({ bucket: "documents", fileName: `${"a".repeat(201)}.pdf`, contentType: "application/pdf" });

  assert.equal(res.status, 400);
});
