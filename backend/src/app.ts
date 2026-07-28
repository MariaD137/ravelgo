import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import { rateLimit } from "express-rate-limit";
import helmet from "helmet";
import morgan from "morgan";
import { env } from "./config/env";
import { adminRouter } from "./routes/admin.routes";
import { alertsRouter } from "./routes/alerts.routes";
import { carPaddyRouter } from "./routes/carpaddy.routes";
import { courierRouter } from "./routes/courier.routes";
import { documentsRouter } from "./routes/documents.routes";
import { driversRouter } from "./routes/drivers.routes";
import { healthRouter } from "./routes/health.routes";
import { paymentsRouter } from "./routes/payments.routes";
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

app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: "Not found" });
});

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});
