import assert from "node:assert/strict";
import { test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { openapiDocument } from "../lib/openapi";
import { listRoutes } from "../lib/route-inventory";

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

// ---------------------------------------------------------------------------
// B-8: the spec must describe the app, not a past version of it
// ---------------------------------------------------------------------------

/**
 * openapi.yaml had drifted 56 operations behind the code — every payout,
 * stay, rental-booking, Eats and Places route was missing, and /health was
 * documented under the /api base it is not served from. A spec that is
 * merely stale is worse than none: someone integrating against it builds for
 * an API that does not exist.
 *
 * This compares the spec to Express's own router stack, so it fails the
 * moment a route is added, removed or renamed without the spec following.
 * Fixing a failure means editing openapi.yaml, not this test.
 */
function specOperations(): Set<string> {
  const ops = new Set<string>();
  const paths = (openapiDocument as { paths?: Record<string, Record<string, unknown>> }).paths ?? {};
  for (const [path, item] of Object.entries(paths)) {
    // A path-item `servers` override means it is NOT under the document's
    // /api base — that is how /health and /openapi.json are described.
    const rooted = Array.isArray((item as { servers?: unknown[] }).servers);
    const full = rooted ? path : `/api${path}`;
    for (const method of Object.keys(item)) {
      if (!["get", "post", "put", "patch", "delete"].includes(method)) continue;
      ops.add(`${method.toUpperCase()} ${full}`);
    }
  }
  return ops;
}

/** Express's ":id" written the way OpenAPI writes it. */
function asSpecPath(route: string): string {
  return route.replace(/:([A-Za-z0-9_]+)/g, "{$1}");
}

test("openapi.yaml documents every route the app actually serves", () => {
  const registered = new Set(listRoutes(app).map(asSpecPath));
  const documented = specOperations();

  const undocumented = [...registered].filter((r) => !documented.has(r)).sort();
  assert.deepEqual(
    undocumented,
    [],
    `these routes exist but openapi.yaml does not describe them:\n  ${undocumented.join("\n  ")}`,
  );
});

test("openapi.yaml describes no route the app does not serve", () => {
  const registered = new Set(listRoutes(app).map(asSpecPath));
  const documented = specOperations();

  const phantom = [...documented].filter((r) => !registered.has(r)).sort();
  assert.deepEqual(
    phantom,
    [],
    `openapi.yaml describes routes that no longer exist:\n  ${phantom.join("\n  ")}`,
  );
});

test("the spec and the app agree on exactly one operation count", () => {
  assert.equal(specOperations().size, listRoutes(app).length);
});
