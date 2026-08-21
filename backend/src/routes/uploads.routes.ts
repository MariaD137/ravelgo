import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth } from "../middleware/auth";

export const uploadsRouter = Router();

const s3 = new S3Client({ region: env.AWS_REGION });

// documents: driver license/insurance/registration scans (PDF or photo).
// assets: vehicle/rental photos and avatars, served publicly through
// CloudFront (see infra/lib/storage-stack.ts) — an unrestricted contentType
// here would let a client store e.g. "text/html" or "image/svg+xml" against
// what's meant to be an image and have CloudFront serve it back with that
// Content-Type, a stored-XSS vector if anyone ever navigates to the asset
// URL directly rather than only embedding it as `<img>`. Restricted to a
// fixed image allowlist for that reason; documents additionally allows PDF.
const ALLOWED_CONTENT_TYPES = {
  documents: ["application/pdf", "image/jpeg", "image/png", "image/webp"],
  assets: ["image/jpeg", "image/png", "image/webp"],
} as const satisfies Record<string, readonly string[]>;

// Letters/digits/spaces/`.`/`-`/`_` only, capped length — S3 keys have no
// real path-traversal risk (a key is an opaque string, not a filesystem
// path), but this keeps the stored key sane and rejects control characters.
const SAFE_FILE_NAME = /^[\w.\- ]{1,200}$/;

const presignSchema = z
  .object({
    bucket: z.enum(["documents", "assets"]),
    fileName: z.string().min(1).max(200).regex(SAFE_FILE_NAME, "fileName contains unsupported characters"),
    contentType: z.string().min(1),
  })
  .refine((data) => (ALLOWED_CONTENT_TYPES[data.bucket] as readonly string[]).includes(data.contentType), {
    message: "Unsupported contentType for this bucket",
    path: ["contentType"],
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
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

  res.json({ uploadUrl, fileKey, expiresIn: 300 });
});
