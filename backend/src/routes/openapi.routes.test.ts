import assert from "node:assert/strict";
import { test } from "node:test";
import request from "supertest";
import { app } from "../app";

test("GET /openapi.json serves the OpenAPI spec", async () => {
  const res = await request(app).get("/openapi.json");
  assert.equal(res.status, 200);
  assert.equal(res.body.openapi, "3.0.3");
  assert.equal(res.body.info.title, "RavelGo API");
  assert.ok(res.body.paths["/health"]);
});

test("GET /docs serves the Swagger UI page", async () => {
  const res = await request(app).get("/docs/");
  assert.equal(res.status, 200);
  assert.match(res.headers["content-type"], /html/);
});
