import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import { rateLimit } from "express-rate-limit";
import helmet from "helmet";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import morgan from "morgan";
import swaggerUi from "swagger-ui-express";
import { load as loadYaml } from "js-yaml";
import { env } from "./config/env";
import { errorHandler } from "./middleware/error-handler";
import { adminRouter } from "./routes/admin.routes";
import { alertsRouter } from "./routes/alerts.routes";
import { billingRouter } from "./routes/billing.routes";
import { carPaddyRouter } from "./routes/carpaddy.routes";
import { courierRouter } from "./routes/courier.routes";
import { documentsRouter } from "./routes/documents.routes";
import { driversRouter } from "./routes/drivers.routes";
import { healthRouter } from "./routes/health.routes";
import { loyaltyRouter } from "./routes/loyalty.routes";
import { paymentsRouter } from "./routes/payments.routes";
import { payoutsRouter } from "./routes/payouts.routes";
import { pricingRouter } from "./routes/pricing.routes";
import { rentalsRouter } from "./routes/rentals.routes";
import { ridersRouter } from "./routes/riders.routes";
import { subscriptionsRouter } from "./routes/subscriptions.routes";
import { supportRouter } from "./routes/support.routes";
import { tripsRouter } from "./routes/trips.routes";
import { uploadsRouter } from "./routes/uploads.routes";
import { vehiclesRouter } from "./routes/vehicles.routes";

export const app = express();

// Mobile clients (the rider/driver/admin apps) don't send an Origin header at
// all, so CORS never applies to them — this only matters for browser-based
// callers. Reflect any origin in dev/test for convenience; in production,
// only ALLOWED_ORIGINS (env.ts throws at boot if that's unset) is allowed.
app.use(
  helmet(),
  cors({ origin: env.NODE_ENV === "production" ? env.ALLOWED_ORIGINS : true }),
);

// Mounted at this one exact path, before express.json(): Stripe signs the
// exact raw request bytes, so parsing the body as JSON first would break
// the signature check in src/routes/billing.routes.ts. Scoped this
// narrowly (not the whole "/api" prefix) so express.raw() doesn't consume
// the body stream for every other /api route before express.json() below
// gets a chance to parse it.
app.use("/api/billing/webhook", express.raw({ type: "application/json" }), billingRouter);

app.use(express.json());
app.use(morgan(env.NODE_ENV === "production" ? "combined" : "dev"));

// Skipped in tests so a suite that fires many requests at one endpoint
// doesn't start seeing 429s from its own load.
if (env.NODE_ENV !== "test") {
  app.use(
    "/api",
    rateLimit({
      windowMs: 15 * 60 * 1000,
      limit: 300,
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );
}

// BE-15: the OpenAPI spec is hand-written (openapi.yaml, project root) rather
// than generated from the zod schemas — served as-is, both raw and via a
// browsable UI, so it's one file to keep in sync as routes change.
const openapiDocument = loadYaml(readFileSync(join(__dirname, "..", "openapi.yaml"), "utf-8")) as object;
app.get("/openapi.json", (_req, res) => res.json(openapiDocument));
app.use("/docs", swaggerUi.serve, swaggerUi.setup(openapiDocument));

app.use(healthRouter);
app.use("/api", driversRouter);
app.use("/api", ridersRouter);
app.use("/api", vehiclesRouter);
app.use("/api", rentalsRouter);
app.use("/api", supportRouter);
app.use("/api", uploadsRouter);
app.use("/api", tripsRouter);
app.use("/api", documentsRouter);
app.use("/api", carPaddyRouter);
app.use("/api", adminRouter);
app.use("/api", courierRouter);
app.use("/api", alertsRouter);
app.use("/api", subscriptionsRouter);
app.use("/api", paymentsRouter);
app.use("/api", loyaltyRouter);
app.use("/api", payoutsRouter);
app.use("/api", pricingRouter);

// 404 handler
app.use((_req: Request, res: Response) => {
  const timestamp = new Date().toISOString();
  res.status(404).json({
    error: {
      code: "NOT_FOUND",
      message: "Endpoint not found",
      timestamp,
    },
  });
});

// Global error handler (must be last)
app.use(errorHandler);
