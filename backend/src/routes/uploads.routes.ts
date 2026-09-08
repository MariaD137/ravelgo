import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";
import { sensitiveLimiter } from "../middleware/rate-limit";

export const uploadsRouter = Router();

const s3 = new S3Client({ region: env.AWS_REGION });

// Documents bucket holds driver license / vehicle / support-ticket scans —
// images or PDF. The assets bucket is served publicly through CloudFront
// (see infra/lib/storage-stack.ts), so it's images only: SVG and HTML are
// deliberately excluded there (and everywhere) since either could carry a
// script that would then execute from the app's own asset origin.
const ALLOWED_CONTENT_TYPES: Record<"documents" | "assets", readonly string[]> = {
  documents: ["image/jpeg", "image/png", "image/webp", "image/heic", "application/pdf"],
  assets: ["image/jpeg", "image/png", "image/webp"],
};

// Server-enforced upload cap, per bucket — documents allows a scanned PDF,
// assets is photos only. Previously nothing capped this server-side; a
// client could declare any size (or none) and PUT an arbitrarily large file.
const MAX_UPLOAD_BYTES: Record<"documents" | "assets", number> = {
  documents: 15 * 1024 * 1024,
  assets: 8 * 1024 * 1024,
};

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  // No path separators or control characters — this is embedded verbatim
  // into the S3 key below, and while S3 keys are opaque strings (a literal
  // ".." doesn't traverse anything the way a filesystem path would), a
  // stray "/" could still make the stored key look like it belongs to a
  // different, unintended virtual "folder" in tooling that lists by prefix.
  fileName: z
    .string()
    .min(1)
    .max(200)
    .regex(/^[^/\\\x00-\x1f]+$/, "fileName must not contain path separators or control characters"),
  contentType: z.string().min(1),
  // The exact byte size the client is about to PUT. Required so the size
  // limit is real: this value is checked against MAX_UPLOAD_BYTES below, and
  // then baked into the presigned URL as ContentLength — S3 itself rejects
  // any PUT whose Content-Length header doesn't match exactly, so a caller
  // can't declare a small size here and then upload something bigger.
  fileSize: z.number().int().positive(),
});

// Any authenticated user: get a short-lived URL to upload a file straight to
// S3. The client PUTs the file bytes to `uploadUrl`, then sends `fileKey`
// back to whichever endpoint records the metadata (e.g. POST /documents).
uploadsRouter.post("/uploads/presign", sensitiveLimiter, requireAuth, async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { bucket, fileName, contentType, fileSize } = parsed.data;

  if (!ALLOWED_CONTENT_TYPES[bucket].includes(contentType)) {
    return res.status(400).json({
      error: `contentType must be one of: ${ALLOWED_CONTENT_TYPES[bucket].join(", ")}`,
    });
  }

  const maxBytes = MAX_UPLOAD_BYTES[bucket];
  if (fileSize > maxBytes) {
    return res.status(400).json({
      error: `File is too large (${(fileSize / (1024 * 1024)).toFixed(1)} MB). Maximum for ${bucket} is ${(maxBytes / (1024 * 1024)).toFixed(0)} MB.`,
    });
  }

  const bucketName = bucket === "documents" ? env.DOCUMENTS_BUCKET : env.ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${bucket} bucket is not configured` });
  }

  const fileKey = `${req.user!.sub}/${randomUUID()}-${fileName}`;

  // ContentLength is part of what gets signed — S3 then requires the actual
  // PUT to carry that exact Content-Length header, so this is a real,
  // server-enforced ceiling, not just a UI/client-side check.
  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: fileKey,
    ContentType: contentType,
    ContentLength: fileSize,
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

  res.json({ uploadUrl, fileKey, expiresIn: 300 });
});
