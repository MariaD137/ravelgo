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

// Strips any path separator or control character from the caller-supplied
// filename before it becomes part of the S3 key — a stray "/" or ".."
// can't escape the fixed `${sub}/${uuid}-` prefix (S3 keys are a flat
// namespace, not a real filesystem), but it can still corrupt the key or
// break tooling that assumes a plain filename, so it's rejected outright
// rather than silently transformed.
function sanitizeFileName(fileName: string): string {
  const base = fileName.split(/[/\\]/).pop() ?? fileName;
  return base.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 200);
}

uploadsRouter.post("/uploads/presign", requireAuth, asyncHandler(async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  // "assets" uploads never land in the publicly-served AssetsBucket
  // directly — they go to PendingAssetsBucket first, which CloudFront has
  // no access to, and only get copied into AssetsBucket by the
  // upload-processor Lambda once magic-byte validation passes. Otherwise
  // a malicious or spoofed file would be publicly fetchable for however
  // long that async check takes. DocumentsBucket doesn't need this: it's
  // never public, only ever read back through a fresh presigned GET the
  // backend issues after re-checking the caller owns the object.
  const bucketName =
    parsed.data.bucket === "documents" ? env.DOCUMENTS_BUCKET : env.PENDING_ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${parsed.data.bucket} bucket is not configured` });
  }

  const sanitized = sanitizeFileName(parsed.data.fileName);
  if (!sanitized) {
    return res.status(400).json({ error: "fileName must contain at least one alphanumeric character" });
  }
  const fileKey = `${req.user!.sub}/${randomUUID()}-${sanitized}`;

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
