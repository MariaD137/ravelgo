import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { env } from "../config/env";
import { mockAuthAs, restoreAuth } from "../test/helpers";
import { __setFetch, type FetchLike } from "../services/places";

// A fetch stub that returns the given body for any URL. Captures the last URL
// so a test can assert what was sent to Google.
let lastUrl = "";
function stubFetch(body: unknown, ok = true, status = 200): FetchLike {
  return async (url: string) => {
    lastUrl = url;
    return { ok, status, json: async () => body };
  };
}

let restoreFetch: FetchLike | null = null;

// Self-contained: CI does not set GOOGLE_MAPS_SERVER_KEY, so install the test
// key before every test instead of relying on the ambient environment. The
// "no key configured" test clears it explicitly for its own scope.
beforeEach(() => {
  env.GOOGLE_MAPS_SERVER_KEY = "test-server-key";
});

afterEach(() => {
  restoreAuth();
  if (restoreFetch) {
    __setFetch(restoreFetch);
    restoreFetch = null;
  }
  env.GOOGLE_MAPS_SERVER_KEY = "test-server-key";
});

test("GET /places/autocomplete returns normalized suggestions for an authed user", async () => {
  restoreFetch = __setFetch(
    stubFetch({
      status: "OK",
      predictions: [
        { place_id: "p1", description: "Lekki Phase 1, Lagos" },
        { place_id: "p2", description: "Lekki Conservation Centre" },
        { description: "no place id — dropped" },
      ],
    }),
  );
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/places/autocomplete?q=lekki")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.suggestions.length, 2);
  assert.deepEqual(res.body.suggestions[0], { placeId: "p1", description: "Lekki Phase 1, Lagos" });
  assert.ok(lastUrl.includes("key=test-server-key"));
});

test("GET /places/autocomplete requires authentication (bot boundary)", async () => {
  restoreFetch = __setFetch(stubFetch({ status: "OK", predictions: [] }));
  const res = await request(app).get("/api/places/autocomplete?q=lekki");
  assert.equal(res.status, 401);
});

test("GET /places/autocomplete rejects a missing query", async () => {
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/places/autocomplete")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 400);
});

test("GET /places/details resolves a place id to an address + coordinates", async () => {
  restoreFetch = __setFetch(
    stubFetch({
      status: "OK",
      result: {
        formatted_address: "Lekki Phase 1, Lagos, Nigeria",
        geometry: { location: { lat: 6.4478, lng: 3.4723 } },
      },
    }),
  );
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/places/details?placeId=p1")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { address: "Lekki Phase 1, Lagos, Nigeria", lat: 6.4478, lng: 3.4723 });
});

test("GET /geocode/reverse returns an address for coordinates", async () => {
  restoreFetch = __setFetch(
    stubFetch({ status: "OK", results: [{ formatted_address: "12 Marina Rd, Lagos" }] }),
  );
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/geocode/reverse?lat=6.45&lng=3.39")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.address, "12 Marina Rd, Lagos");
});

test("GET /geocode/reverse returns address:null when nothing matched", async () => {
  restoreFetch = __setFetch(stubFetch({ status: "ZERO_RESULTS", results: [] }));
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/geocode/reverse?lat=0&lng=0")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.address, null);
});

test("places proxy returns 503 when no server key is configured", async () => {
  env.GOOGLE_MAPS_SERVER_KEY = undefined;
  restoreFetch = __setFetch(stubFetch({ status: "OK", predictions: [] }));
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/places/autocomplete?q=lekki")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 503);
});

test("places proxy maps an upstream Google error to 502 without leaking detail", async () => {
  restoreFetch = __setFetch(
    stubFetch({ status: "REQUEST_DENIED", error_message: "The provided API key is invalid." }),
  );
  const token = mockAuthAs({ sub: "rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/places/autocomplete?q=lekki")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 502);
  assert.ok(!JSON.stringify(res.body).includes("API key"));
});

// Forward geocoding — the fallback that keeps booking possible when the device
// gives the app no coordinates (location denied, or the map never loaded).

test("GET /geocode/forward turns a typed address into coordinates", async () => {
  restoreFetch = __setFetch(
    stubFetch({
      status: "OK",
      results: [
        {
          formatted_address: "Lekki Phase 1, Lagos, Nigeria",
          geometry: { location: { lat: 6.4474, lng: 3.4736 } },
        },
      ],
    }),
  );
  const token = mockAuthAs({ sub: "rider-fwd-1", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/geocode/forward?q=Lekki%20Phase%201")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.address, "Lekki Phase 1, Lagos, Nigeria");
  assert.equal(res.body.lat, 6.4474);
  assert.equal(res.body.lng, 3.4736);
  assert.ok(lastUrl.includes("geocode/json"));
});

test("GET /geocode/forward 404s when the address matches nothing", async () => {
  restoreFetch = __setFetch(stubFetch({ status: "ZERO_RESULTS", results: [] }));
  const token = mockAuthAs({ sub: "rider-fwd-2", groups: ["Rider"] });
  const res = await request(app)
    .get("/api/geocode/forward?q=nowhere%20at%20all")
    .set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});

test("GET /geocode/forward requires authentication", async () => {
  const res = await request(app).get("/api/geocode/forward?q=Lekki");
  assert.equal(res.status, 401);
});
