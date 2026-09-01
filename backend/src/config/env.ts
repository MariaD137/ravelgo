import "dotenv/config";
import { z } from "zod";

const rawEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(8080),
  // Either provide DATABASE_URL directly (local dev), or the individual parts
  // below and it'll be assembled at boot (how App Runner injects RDS
  // credentials from Secrets Manager — see infra/lib/api-stack.ts).
  DATABASE_URL: z.string().optional(),
  DB_HOST: z.string().optional(),
  DB_PORT: z.coerce.number().default(5432),
  DB_NAME: z.string().default("ravelgo"),
  DB_USERNAME: z.string().optional(),
  DB_PASSWORD: z.string().optional(),
  COGNITO_USER_POOL_ID: z.string().min(1, "COGNITO_USER_POOL_ID is required"),
  COGNITO_CLIENT_ID: z.string().min(1, "COGNITO_CLIENT_ID is required"),
  AWS_REGION: z.string().default("us-east-1"),
  DOCUMENTS_BUCKET: z.string().optional(),
  ASSETS_BUCKET: z.string().optional(),
  // Comma-separated list of allowed origins for CORS, e.g.
  // "https://app.ravelgo.com,https://admin.ravelgo.com". Empty in
  // development so local Flutter/web dev builds on arbitrary ports aren't
  // blocked; required to actually allow any cross-origin request once
  // NODE_ENV is production (enforced below, not by zod, so the message names
  // the real cause instead of a generic schema error).
  ALLOWED_ORIGINS: z.string().optional(),
  // Optional: unset in dev/test (Stripe-backed routes give a clear 500
  // instead of silently no-opping — see src/billing/stripe.ts). Required in
  // production, enforced below rather than by zod so the error names the
  // real cause.
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  // Server-side Google Maps Platform key used by the Places/Geocoding proxy
  // (src/routes/places.routes.ts). Deliberately separate from the browser
  // Maps-JS key the web apps embed: this one is never sent to a client, so it
  // can be locked to the backend's egress IP / specific APIs instead of an HTTP
  // referrer. Optional so dev/test boots without it (the proxy returns a clear
  // 503 when it's unset rather than calling Google with an empty key).
  GOOGLE_MAPS_SERVER_KEY: z.string().optional(),
});

export interface Env {
  NODE_ENV: "development" | "test" | "production";
  PORT: number;
  DATABASE_URL: string;
  COGNITO_USER_POOL_ID: string;
  COGNITO_CLIENT_ID: string;
  AWS_REGION: string;
  DOCUMENTS_BUCKET?: string;
  ASSETS_BUCKET?: string;
  ALLOWED_ORIGINS: string[];
  STRIPE_SECRET_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  GOOGLE_MAPS_SERVER_KEY?: string;
}

function loadEnv(): Env {
  const parsed = rawEnvSchema.safeParse(process.env);
  if (!parsed.success) {
    console.error("Invalid environment configuration:", parsed.error.flatten().fieldErrors);
    throw new Error("Invalid environment configuration");
  }
  const data = parsed.data;

  let databaseUrl = data.DATABASE_URL;
  if (!databaseUrl) {
    if (!data.DB_HOST || !data.DB_USERNAME || !data.DB_PASSWORD) {
      throw new Error(
        "Set either DATABASE_URL, or DB_HOST + DB_USERNAME + DB_PASSWORD (DB_PORT/DB_NAME have defaults)",
      );
    }
    const user = encodeURIComponent(data.DB_USERNAME);
    const pass = encodeURIComponent(data.DB_PASSWORD);
    // sslmode=require: encrypt the connection without verifying the server
    // certificate. RDS PostgreSQL 15+ default parameter groups set
    // rds.force_ssl=1, so a plaintext connection is refused outright. This
    // applies only to the URL assembled from split DB_* vars (the cloud
    // deployment path); a caller who supplies a full DATABASE_URL controls
    // their own sslmode.
    databaseUrl = `postgresql://${user}:${pass}@${data.DB_HOST}:${data.DB_PORT}/${data.DB_NAME}?sslmode=require`;
  }

  // Prisma reads its connection string straight from process.env.DATABASE_URL
  // (prisma/schema.prisma: `url = env("DATABASE_URL")`) — it does NOT see the
  // value we resolve here. In deployments that provide the split
  // DB_HOST/DB_USERNAME/DB_PASSWORD vars instead of a ready-made DATABASE_URL
  // (e.g. App Runner reading DB creds from Secrets Manager), nothing else sets
  // it, so `new PrismaClient()` throws at construction — before the server can
  // bind a port or log a line. Publish the resolved URL back to the
  // environment so Prisma picks it up. No-op when DATABASE_URL was already set.
  process.env.DATABASE_URL = databaseUrl;

  const allowedOrigins = (data.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);

  if (data.NODE_ENV === "production" && allowedOrigins.length === 0) {
    throw new Error("ALLOWED_ORIGINS is required in production (comma-separated list of allowed origins)");
  }
  if (data.NODE_ENV === "production" && (!data.STRIPE_SECRET_KEY || !data.STRIPE_WEBHOOK_SECRET)) {
    throw new Error("STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET are required in production");
  }

  return {
    NODE_ENV: data.NODE_ENV,
    PORT: data.PORT,
    DATABASE_URL: databaseUrl,
    COGNITO_USER_POOL_ID: data.COGNITO_USER_POOL_ID,
    COGNITO_CLIENT_ID: data.COGNITO_CLIENT_ID,
    AWS_REGION: data.AWS_REGION,
    DOCUMENTS_BUCKET: data.DOCUMENTS_BUCKET,
    ASSETS_BUCKET: data.ASSETS_BUCKET,
    ALLOWED_ORIGINS: allowedOrigins,
    STRIPE_SECRET_KEY: data.STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET: data.STRIPE_WEBHOOK_SECRET,
    GOOGLE_MAPS_SERVER_KEY: data.GOOGLE_MAPS_SERVER_KEY,
  };
}

export const env = loadEnv();
