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
  // 32-byte AES-256-GCM key (base64), used to encrypt bank account/routing
  // numbers at rest — see src/lib/encryption.ts. Optional in dev/test
  // (encryption.ts falls back to a fixed dev-only key there); required in
  // production, enforced below rather than by zod so the error names the
  // real cause. Generate with: openssl rand -base64 32
  FIELD_ENCRYPTION_KEY: z.string().optional(),
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
  FIELD_ENCRYPTION_KEY?: string;
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
    databaseUrl = `postgresql://${user}:${pass}@${data.DB_HOST}:${data.DB_PORT}/${data.DB_NAME}`;
  }

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
  if (data.NODE_ENV === "production" && !data.FIELD_ENCRYPTION_KEY) {
    throw new Error("FIELD_ENCRYPTION_KEY is required in production (32-byte base64 key)");
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
    FIELD_ENCRYPTION_KEY: data.FIELD_ENCRYPTION_KEY,
  };
}

export const env = loadEnv();
