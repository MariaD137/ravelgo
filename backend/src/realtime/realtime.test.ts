import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { after, afterEach, before, beforeEach, test } from "node:test";
import type { AddressInfo } from "node:net";
import request from "supertest";
import WebSocket from "ws";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";
import { attachRealtime } from "./server";
import { resetRealtimeState } from "./hub";

let server: Server;
let baseUrl: string;
let wsUrl: string;

before(async () => {
  server = createServer(app);
  attachRealtime(server);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const { port } = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${port}`;
  wsUrl = `ws://127.0.0.1:${port}/ws`;
});

beforeEach(async () => {
  await resetDb();
  resetRealtimeState();
});
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
  await new Promise((resolve) => server.close(resolve));
});

function waitForMessage(socket: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("timed out waiting for a WS message")), 2000);
    socket.once("message", (raw) => {
      clearTimeout(timeout);
      resolve(JSON.parse(raw.toString()));
    });
  });
}

function waitForOpen(socket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.once("open", () => resolve());
    socket.once("error", reject);
  });
}

function waitForClose(socket: WebSocket): Promise<number> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("timed out waiting for the socket to close")), 2000);
    socket.once("close", (code) => {
      clearTimeout(timeout);
      resolve(code);
    });
  });
}

async function createRiderDriverTrip() {
  const rider = await prisma.user.create({
    data: { cognitoSub: "rider-sub-1", role: "RIDER", firstName: "A", lastName: "B", email: "a@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "driver-sub-1", role: "DRIVER", firstName: "C", lastName: "D", email: "c@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: { riderId: rider.id, driverId: driver.id, pickup: "X", destination: "Y", estimatedFare: 20, status: "MATCHED" },
  });
  return { rider, driver, trip };
}

test("WS connection with no token is closed with 4401", async () => {
  const socket = new WebSocket(wsUrl);
  const code = await waitForClose(socket);
  assert.equal(code, 4401);
});

test("WS connection with an invalid token is closed with 4401", async () => {
  mockAuthAs({ sub: "someone", groups: ["Rider"] }); // mocks verify() to only accept its own token
  const socket = new WebSocket(`${wsUrl}?token=not-the-mocked-token`);
  const code = await waitForClose(socket);
  assert.equal(code, 4401);
});

test("subscribe rejects a user who isn't party to the trip", async () => {
  const { trip } = await createRiderDriverTrip();
  const token = mockAuthAs({ sub: "stranger-sub", groups: ["Rider"] });

  const socket = new WebSocket(`${wsUrl}?token=${token}`);
  try {
    await waitForOpen(socket);
    socket.send(JSON.stringify({ type: "subscribe", tripId: trip.id }));
    const reply = await waitForMessage(socket);
    assert.equal(reply.type, "error");
  } finally {
    // A failed assertion above must not skip this: an open socket keeps
    // the http.Server "busy", so after()'s server.close() would hang
    // waiting for it forever instead of failing the run — one bad
    // assertion should not turn into an unbounded CI job.
    socket.close();
  }
});

test("subscribe accepts the rider on the trip, and PATCH .../status broadcasts trip:status", async () => {
  const { rider, trip } = await createRiderDriverTrip();
  const token = mockAuthAs({ sub: rider.cognitoSub, groups: ["Rider"] });

  const socket = new WebSocket(`${wsUrl}?token=${token}`);
  try {
    await waitForOpen(socket);
    socket.send(JSON.stringify({ type: "subscribe", tripId: trip.id }));
    const subAck = await waitForMessage(socket);
    assert.equal(subAck.type, "subscribed");

    const statusPromise = waitForMessage(socket);
    restoreAuth();
    const driverToken = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
    const res = await request(baseUrl)
      .patch(`/api/trips/${trip.id}/status`)
      .set("Authorization", `Bearer ${driverToken}`)
      .send({ status: "IN_PROGRESS" });
    assert.equal(res.status, 200);

    const broadcast = await statusPromise;
    assert.equal(broadcast.type, "trip:status");
    assert.equal(broadcast.tripId, trip.id);
    assert.equal(broadcast.status, "IN_PROGRESS");
  } finally {
    socket.close();
  }
});

test("a driver's location message broadcasts to a subscribed rider, and the HTTP fallback reflects it", async () => {
  const { rider, driver, trip } = await createRiderDriverTrip();
  const riderToken = mockAuthAs({ sub: rider.cognitoSub, groups: ["Rider"] });

  const riderSocket = new WebSocket(`${wsUrl}?token=${riderToken}`);
  let driverSocket: WebSocket | undefined;
  try {
    await waitForOpen(riderSocket);
    riderSocket.send(JSON.stringify({ type: "subscribe", tripId: trip.id }));
    await waitForMessage(riderSocket); // "subscribed" ack

    restoreAuth();
    const driverToken = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });
    driverSocket = new WebSocket(`${wsUrl}?token=${driverToken}`);
    await waitForOpen(driverSocket);

    const locationPromise = waitForMessage(riderSocket);
    driverSocket.send(JSON.stringify({ type: "location", lat: 6.5, lng: 3.4 }));
    const broadcast = await locationPromise;

    assert.equal(broadcast.type, "location");
    assert.equal(broadcast.tripId, trip.id);
    assert.equal(broadcast.driverId, driver.id);
    assert.equal(broadcast.lat, 6.5);

    // The WS connections above already authenticated at connect time — but
    // the HTTP fallback call below re-verifies on every request, so the mock
    // has to be switched back to accept riderToken (same underlying token
    // string, since mockAuthAs is deterministic per sub).
    restoreAuth();
    mockAuthAs({ sub: rider.cognitoSub, groups: ["Rider"] });
    const fallback = await request(baseUrl)
      .get(`/api/trips/${trip.id}/driver-location`)
      .set("Authorization", `Bearer ${riderToken}`);
    assert.equal(fallback.status, 200);
    assert.equal(fallback.body.lat, 6.5);
  } finally {
    riderSocket.close();
    driverSocket?.close();
  }
});

test("GET /trips/:id/driver-location 404s before any location has been reported", async () => {
  const { rider, trip } = await createRiderDriverTrip();
  const token = mockAuthAs({ sub: rider.cognitoSub, groups: ["Rider"] });

  const res = await request(baseUrl).get(`/api/trips/${trip.id}/driver-location`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});
