import assert from "node:assert/strict";
import { test } from "node:test";
import express from "express";
import request from "supertest";
import { errorHandler } from "./error-handler";
import { Errors } from "../lib/errors";

// A throwaway app that lets each test throw a chosen error into the handler.
function appThatThrows(err: unknown) {
  const app = express();
  app.get("/boom", (_req, _res, next) => next(err));
  app.use(errorHandler);
  return app;
}

test("an unexpected (non-Api) error becomes a generic 500 with no stack trace or internals", async () => {
  // A raw error whose message would be sensitive if echoed to the client.
  const leaky = new Error("connect ECONNREFUSED 10.0.3.14:5432 password=hunter2");
  const res = await request(appThatThrows(leaky)).get("/boom");

  assert.equal(res.status, 500);
  assert.equal(res.body.error.code, "INTERNAL_SERVER_ERROR");
  assert.equal(res.body.error.message, "Internal server error");
  // None of the raw error's contents leak to the client.
  const serialized = JSON.stringify(res.body);
  assert.doesNotMatch(serialized, /ECONNREFUSED/);
  assert.doesNotMatch(serialized, /hunter2/);
  assert.doesNotMatch(serialized, /10\.0\.3\.14/);
  assert.equal(res.body.error.stack, undefined);
});

test("a deliberate ApiError keeps its intended status and safe message", async () => {
  const res = await request(appThatThrows(Errors.conflict("Trip has already been charged"))).get("/boom");
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, "CONFLICT");
  assert.equal(res.body.error.message, "Trip has already been charged");
});

test("a simulated Prisma known-request error returns a safe generic message, not the raw DB error", async () => {
  const prismaLike = Object.assign(new Error("Invalid `prisma.user.update()` invocation: internal column detail"), {
    name: "PrismaClientKnownRequestError",
    code: "P2025",
  });
  const res = await request(appThatThrows(prismaLike)).get("/boom");

  assert.equal(res.status, 404);
  assert.equal(res.body.error.message, "Record not found");
  assert.doesNotMatch(JSON.stringify(res.body), /prisma\.user\.update|internal column detail/);
});
