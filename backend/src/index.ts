import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import helmet from "helmet";
import morgan from "morgan";
import { env } from "./config/env";
import { adminRouter } from "./routes/admin.routes";
import { carPaddyRouter } from "./routes/carpaddy.routes";
import { documentsRouter } from "./routes/documents.routes";
import { driversRouter } from "./routes/drivers.routes";
import { healthRouter } from "./routes/health.routes";
import { tripsRouter } from "./routes/trips.routes";

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan(env.NODE_ENV === "production" ? "combined" : "dev"));

app.use(healthRouter);
app.use("/api", driversRouter);
app.use("/api", tripsRouter);
app.use("/api", documentsRouter);
app.use("/api", carPaddyRouter);
app.use("/api", adminRouter);

app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: "Not found" });
});

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});

app.listen(env.PORT, () => {
  console.log(`RavelGo backend listening on port ${env.PORT} (${env.NODE_ENV})`);
});
