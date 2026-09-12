import { Router } from "express";
import { paystackConfig } from "../billing/paystack";
import { prisma } from "../db/prisma";

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
