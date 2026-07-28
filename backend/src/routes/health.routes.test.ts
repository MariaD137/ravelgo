import assert from "node:assert/strict";
import { after, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";

after(async () => {
  await prisma.$disconnect();
});

test("GET /health reports ok when the database is reachable", async () => {
  const res = await request(app).get("/health");
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "ok");
  assert.equal(res.body.database, "connected");
});
