import type { Express } from "express";

/**
 * Every HTTP route this Express app actually serves, as "METHOD /path"
 * strings with the mount prefixes resolved ("POST /api/trips", not the bare
 * "POST /trips" the router itself was written with).
 *
 * This exists so openapi.yaml can be checked against the real app rather
 * than trusted (see routes/openapi.routes.test.ts). The spec had drifted 56
 * operations behind the code, which makes it worse than no spec: anyone
 * integrating against it built for an API that no longer matched.
 *
 * It reads Express's own router stack, so it needs no registry to be kept up
 * to date by hand — a route that exists is listed, whether or not anyone
 * remembered it.
 */
export function listRoutes(app: Express): string[] {
  const found: string[] = [];
  walk(routerStackOf(app), "");
  return [...new Set(found)].sort();

  function walk(stack: Layer[] | undefined, prefix: string): void {
    for (const layer of stack ?? []) {
      if (layer.route) {
        const path = joinPath(prefix, layer.route.path);
        for (const [method, enabled] of Object.entries(layer.route.methods ?? {})) {
          // Express registers an implicit HEAD alongside every GET, and
          // `app.all`-style "_all" entries are not real operations.
          if (!enabled || method === "_all" || method === "head") continue;
          found.push(`${method.toUpperCase()} ${path}`);
        }
      } else if (layer.handle?.stack) {
        walk(layer.handle.stack, joinPath(prefix, mountPathOf(layer)));
      }
    }
  }
}

interface Layer {
  route?: { path: string; methods: Record<string, boolean> };
  handle?: { stack?: Layer[] };
  regexp?: RegExp;
  path?: string;
}

function routerStackOf(app: Express): Layer[] {
  // Express 4 keeps it on _router; Express 5 exposes app.router.
  const anyApp = app as unknown as { _router?: { stack: Layer[] }; router?: { stack: Layer[] } };
  return anyApp._router?.stack ?? anyApp.router?.stack ?? [];
}

/**
 * The prefix a sub-router was mounted at. Express does not keep the literal
 * string, only the regexp it compiled, so this reverses the shapes Express
 * actually produces: "/api" -> /^\/api\/?(?=\/|$)/i, and the "mounted at
 * root" case, whose regexp matches everything and contributes no prefix.
 */
function mountPathOf(layer: Layer): string {
  if (typeof layer.path === "string" && layer.path.length > 0) return layer.path;
  const source = layer.regexp?.source;
  if (!source || source === "^\\/?(?=\\/|$)" || source === "^\\/?$") return "";
  const match = /^\^((?:\\\/[^\\^$?*+()[\]{}|]+)+)/.exec(source);
  if (!match) return "";
  return match[1].replace(/\\\//g, "/");
}

function joinPath(prefix: string, path: string): string {
  const joined = `${prefix}${path}`.replace(/\/{2,}/g, "/");
  if (joined.length > 1 && joined.endsWith("/")) return joined.slice(0, -1);
  return joined === "" ? "/" : joined;
}
