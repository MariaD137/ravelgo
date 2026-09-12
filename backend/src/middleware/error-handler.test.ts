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

test("a Paystack rejection becomes a 502 PAYMENT_PROVIDER_ERROR with a safe message", async () => {
  const providerErr = Object.assign(new Error("Invalid key"), { name: "PaystackApiError", status: 401 });
  const res = await request(appThatThrows(providerErr)).get("/boom");

  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "PAYMENT_PROVIDER_ERROR");
  assert.equal(res.body.error.message, "The payment provider could not process this request");
  // Paystack's raw message stays in the server log, never in the response.
  assert.doesNotMatch(JSON.stringify(res.body), /Invalid key/);
});

test("an unconfigured Paystack key (status 503) is reported as payments-not-configured, not a generic 500", async () => {
  const unconfigured = Object.assign(new Error("PAYSTACK_SECRET_KEY is placeholder ..."), {
    name: "PaystackApiError",
    status: 503,
  });
  const res = await request(appThatThrows(unconfigured)).get("/boom");

  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, "PAYMENT_PROVIDER_ERROR");
  assert.equal(res.body.error.message, "Payments are not configured on this server yet");
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
