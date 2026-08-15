import { S3Client } from "@aws-sdk/client-s3";
import { createPresignedPost } from "@aws-sdk/s3-presigned-post";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";

export const uploadsRouter = Router();

const s3 = new S3Client({ region: env.AWS_REGION });

const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10 MB

const ALLOWED_CONTENT_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "application/pdf",
];

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  fileName: z.string().min(1),
  contentType: z.enum(ALLOWED_CONTENT_TYPES as [string, ...string[]]),
});

uploadsRouter.post("/uploads/presign", requireAuth, asyncHandler(async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const bucketName = parsed.data.bucket === "documents" ? env.DOCUMENTS_BUCKET : env.ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${parsed.data.bucket} bucket is not configured` });
  }

  const fileKey = `${req.user!.sub}/${randomUUID()}-${parsed.data.fileName}`;

  const { url, fields } = await createPresignedPost(s3, {
    Bucket: bucketName,
    Key: fileKey,
    Conditions: [
      ["content-length-range", 1, MAX_UPLOAD_BYTES],
      ["eq", "$Content-Type", parsed.data.contentType],
    ],
    Fields: { "Content-Type": parsed.data.contentType },
    Expires: 300,
  });

  res.json({ url, fields, fileKey, maxBytes: MAX_UPLOAD_BYTES, expiresIn: 300 });
}));
