import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";

export const uploadsRouter = Router();

const s3 = new S3Client({ region: env.AWS_REGION });

const ALLOWED_CONTENT_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "application/pdf",
];

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  fileName: z.string().min(1),
  contentType: z.enum(ALLOWED_CONTENT_TYPES as [string, ...string[]]),
});

// Any authenticated user: get a short-lived URL to upload a file straight to
// S3. The client PUTs the file bytes to `uploadUrl`, then sends `fileKey`
// back to whichever endpoint records the metadata (e.g. POST /documents).
uploadsRouter.post("/uploads/presign", requireAuth, async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const bucketName = parsed.data.bucket === "documents" ? env.DOCUMENTS_BUCKET : env.ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${parsed.data.bucket} bucket is not configured` });
  }

  const fileKey = `${req.user!.sub}/${randomUUID()}-${parsed.data.fileName}`;

  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: fileKey,
    ContentType: parsed.data.contentType,
    ContentLength: MAX_FILE_SIZE,
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

  res.json({ uploadUrl, fileKey, expiresIn: 300 });
});
