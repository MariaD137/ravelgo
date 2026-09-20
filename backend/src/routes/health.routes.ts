import { readdirSync } from "node:fs";
import { join } from "node:path";
import { Router } from "express";
import { paystackConfig } from "../billing/paystack";
import { prisma } from "../db/prisma";
import { pricingDiagnostics } from "../services/pricing";

export const healthRouter = Router();

// `paystack` reports only whether a usable key is configured (and test/live
// mode) — never the key. It lets a deploy be verified from the outside
// ("is staging actually able to take payments?") without reading App Runner
// logs. It deliberately does NOT affect the HTTP status: a service with
// payments unconfigured is degraded, not down, and App Runner's health check
// (infra/lib/api-stack.ts) would otherwise recycle instances for a config gap.
healthRouter.get("/health", async (_req, res) => {
  const paystack = paystackConfig.configured ? `configured (${paystackConfig.mode})` : `unconfigured (${paystackConfig.reason})`;
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: "ok", database: "connected", paystack, timestamp: new Date().toISOString() });
  } catch {
    res.status(503).json({ status: "degraded", database: "unreachable", paystack, timestamp: new Date().toISOString() });
  }
});

// Read-only diagnostics for the ride-pricing path GET /api/pricing/categories
// depends on, so "Fares unavailable" in the rider app can be traced from the
// outside (curl, or the post-deploy probe in .github/workflows/*-deploy.yml)
// without App Runner log access. Reports only row counts and flags — no
// rates, no PII, no secrets — which is why it needs no auth. A Prisma
// failure here (typically P2021 "table does not exist" because
// scripts/migrate-<env>.sh was never run after the pricing migration) is
// reported as 503 with the Prisma error code, not swallowed.
healthRouter.get("/health/pricing", async (_req, res) => {
  try {
    // rideCategories.total of 0 is fine on a fresh database: GET
    // /api/pricing/categories seeds the four reference categories on first
    // use (services/pricing.ts).
    const diagnostics = await pricingDiagnostics();
    res.json({ status: "ok", ...diagnostics, timestamp: new Date().toISOString() });
  } catch (err) {
    const e = err as { name?: string; code?: string; message?: string };
    console.error("[health] /health/pricing failed:", err);
    const schemaMissing = e.code === "P2021" || e.code === "P2022";
    res.status(503).json({
      status: "error",
      error: {
        name: e.name ?? "Error",
        code: e.code ?? null,
        hint: schemaMissing
          ? "Database schema is out of date: run scripts/migrate-<env>.sh to apply pending Prisma migrations, then retry."
          : "Database query failed; see the service logs for the full error.",
      },
      timestamp: new Date().toISOString(),
    });
  }
});

/**
 * Which Prisma migrations this image expects, and which the database it is
 * talking to has actually applied.
 *
 * This exists because a deploy could report fully green while the whole
 * driver and rental surface was returning "Database schema is out of date on
 * this server": the post-deploy smoke test probed /health, /health/pricing
 * and the fare endpoint, and none of those touch the tables a missing
 * migration had broken. The failure was real, user-facing and completely
 * invisible to CI.
 *
 * Migrations deliberately stay a separate manual step (see
 * scripts/migrate-env.sh for why — the database has no public endpoint and
 * the deploy role has no IAM self-service), so this does NOT apply anything
 * and does not block a deploy. It just makes the gap impossible to miss:
 * the running container ships its own prisma/migrations directory, so it can
 * compare what it expects against _prisma_migrations and say exactly which
 * names are outstanding.
 *
 * Safe to expose unauthenticated, like /health/pricing: migration directory
 * names are not secrets, and nothing here reveals data, credentials or
 * connection details.
 */
healthRouter.get("/health/schema", async (_req, res) => {
  try {
    const expected = readdirSync(join(__dirname, "..", "..", "prisma", "migrations"), {
      withFileTypes: true,
    })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort();

    const rows = await prisma.$queryRaw<
      { migration_name: string; finished_at: Date | null; rolled_back_at: Date | null }[]
    >`SELECT migration_name, finished_at, rolled_back_at FROM "_prisma_migrations"`;

    const applied = rows.filter((r) => r.finished_at !== null && r.rolled_back_at === null);
    const appliedNames = new Set(applied.map((r) => r.migration_name));
    // Started but never finished, or explicitly rolled back: `migrate deploy`
    // refuses to continue past one of these, so it needs naming separately
    // from "simply not run yet".
    const failed = rows
      .filter((r) => r.finished_at === null || r.rolled_back_at !== null)
      .map((r) => r.migration_name);
    const pending = expected.filter((name) => !appliedNames.has(name));

    const healthy = pending.length === 0 && failed.length === 0;
    res.status(healthy ? 200 : 503).json({
      status: healthy ? "ok" : "out-of-date",
      expected: expected.length,
      applied: applied.length,
      pending,
      failed,
      remedy: healthy ? undefined : "Run scripts/migrate-<env>.sh against this environment.",
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    const e = err as { code?: string; message?: string };
    console.error("[health] /health/schema failed:", err);
    res.status(503).json({
      status: "error",
      error: { code: e.code ?? "UNKNOWN", message: "Could not read the migration state" },
      timestamp: new Date().toISOString(),
    });
  }
});
