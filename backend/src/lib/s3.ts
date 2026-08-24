import { S3Client } from "@aws-sdk/client-s3";
import { env } from "../config/env";

// Single shared client — every route that talks to S3 (uploads presign,
// document/photo retrieval) reuses this instead of constructing its own.
export const s3 = new S3Client({ region: env.AWS_REGION });
