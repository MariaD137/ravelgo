import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";

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
});

// Any authenticated user: get a short-lived URL to upload a file straight to
// S3. The client PUTs the file bytes to `uploadUrl`, then sends `fileKey`
// back to whichever endpoint records the metadata (e.g. POST /documents).
uploadsRouter.post("/uploads/presign", requireAuth, async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { bucket, fileName, contentType } = parsed.data;

  if (!ALLOWED_CONTENT_TYPES[bucket].includes(contentType)) {
    return res.status(400).json({
      error: `contentType must be one of: ${ALLOWED_CONTENT_TYPES[bucket].join(", ")}`,
    });
  }

  const bucketName = bucket === "documents" ? env.DOCUMENTS_BUCKET : env.ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${bucket} bucket is not configured` });
  }

  const fileKey = `${req.user!.sub}/${randomUUID()}-${fileName}`;

  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: fileKey,
    ContentType: contentType,
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

  res.json({ uploadUrl, fileKey, expiresIn: 300 });
});
