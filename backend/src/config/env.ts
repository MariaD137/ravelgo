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

  return {
    NODE_ENV: data.NODE_ENV,
    PORT: data.PORT,
    DATABASE_URL: databaseUrl,
    COGNITO_USER_POOL_ID: data.COGNITO_USER_POOL_ID,
    COGNITO_CLIENT_ID: data.COGNITO_CLIENT_ID,
    AWS_REGION: data.AWS_REGION,
    DOCUMENTS_BUCKET: data.DOCUMENTS_BUCKET,
    ASSETS_BUCKET: data.ASSETS_BUCKET,
  };
}

export const env = loadEnv();
