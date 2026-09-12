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
