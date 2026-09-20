import { readFileSync } from "node:fs";
import { join } from "node:path";
import { load as loadYaml } from "js-yaml";

/**
 * The single parsed copy of openapi.yaml, shared by the served document
 * (GET /openapi.json, /docs) and the drift test that checks it still
 * describes the routes this app actually registers
 * (routes/openapi.routes.test.ts, with lib/route-inventory.ts).
 */
export const openapiDocument = loadYaml(
  readFileSync(join(__dirname, "..", "..", "openapi.yaml"), "utf-8"),
) as object;
