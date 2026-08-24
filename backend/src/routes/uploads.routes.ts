import { createPresignedPost } from "@aws-sdk/s3-presigned-post";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth, requireRole } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";
import { s3 } from "../lib/s3";

export const uploadsRouter = Router();

// Only Driver/Admin ever need to write into either bucket today — vehicle
// photos, verification documents, and (for Admin) nothing yet, but never a
// Rider. Kept narrow deliberately; widen only when a real caller needs it.
const UPLOAD_ROLES = ["Driver", "Admin"] as const;

// Per-bucket allowlists, kept in sync with the upload-processor Lambda's
// own ALLOWED_MIME_BY_BUCKET (infra/lambda/upload-processor/index.ts) —
// that Lambda re-validates the real magic bytes after the object lands in
// S3 and silently deletes anything outside this set, so drifting the two
// lists apart just means a client-accepted upload gets thrown away later
// with no explanation. "documents" accepts scanned/photographed paperwork
// (PDF or photo, including HEIC/HEIF — the default format on recent
// iPhones); "assets" (vehicle photos) is images only, no PDF.
const ALLOWED_CONTENT_TYPES: Record<"documents" | "assets", readonly string[]> = {
  documents: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf"],
  assets: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"],
};

// content-length-range is the POST-policy equivalent of the old PUT
// approach's ContentLength binding: S3 rejects the upload outright if the
// actual bytes fall outside this range, so a client can't use a
// once-issued URL to push more than this many bytes.
const MAX_BYTES: Record<"documents" | "assets", number> = {
  documents: 10 * 1024 * 1024, // 10MB — scanned documents/photos of paperwork
  assets: 8 * 1024 * 1024, // 8MB — vehicle photos
};

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  fileName: z.string().min(1),
  contentType: z.string().min(1),
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

// Driver/Admin: get a short-lived S3 POST policy to upload a file straight
// to S3. The client POSTs the file bytes (with the returned `fields`) to
// `url`, then sends `fileKey` back to whichever endpoint records the
// metadata (POST /documents, POST /vehicles/:id/photos). Neither of those
// endpoints trusts an arbitrary client-supplied fileKey — they verify it
// was issued to the calling user (see their own ownership checks).
//
// "assets" uploads never land in the publicly-served AssetsBucket directly
// — they go to PendingAssetsBucket first, which CloudFront has no access
// to, and only get copied into AssetsBucket by the upload-processor Lambda
// once magic-byte validation (and, for images, EXIF stripping) passes.
// Otherwise a malicious or spoofed file would be publicly fetchable for
// however long that async check takes. The Lambda promotes the object
// under the *same* key, so a fileKey/URL built from it stays valid once
// promotion completes — see lib/assetUrl.ts. DocumentsBucket doesn't need
// a staging bucket: it's never public, only ever read back through a
// fresh presigned GET the backend issues after re-checking the caller
// owns the object (see GET /documents/:id/view), so the same Lambda
// validates/tags it in place instead of promoting it anywhere.
uploadsRouter.post(
  "/uploads/presign",
  requireAuth,
  requireRole(...UPLOAD_ROLES),
  asyncHandler(async (req, res) => {
    const parsed = presignSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
    const { bucket, fileName, contentType } = parsed.data;

    if (!ALLOWED_CONTENT_TYPES[bucket].includes(contentType)) {
      return res.status(400).json({
        error: `Unsupported content type for ${bucket}. Allowed: ${ALLOWED_CONTENT_TYPES[bucket].join(", ")}`,
      });
    }

    const bucketName = bucket === "documents" ? env.DOCUMENTS_BUCKET : env.PENDING_ASSETS_BUCKET;
    if (!bucketName) {
      return res.status(500).json({ error: `${bucket} bucket is not configured` });
    }

    const sanitized = sanitizeFileName(fileName);
    if (!sanitized) {
      return res.status(400).json({ error: "fileName must contain at least one alphanumeric character" });
    }
    const fileKey = `${req.user!.sub}/${randomUUID()}-${sanitized}`;
    const maxBytes = MAX_BYTES[bucket];

    const { url, fields } = await createPresignedPost(s3, {
      Bucket: bucketName,
      Key: fileKey,
      Conditions: [
        ["content-length-range", 1, maxBytes],
        ["eq", "$Content-Type", contentType],
      ],
      Fields: { "Content-Type": contentType },
      Expires: 300,
    });

    res.json({ url, fields, fileKey, maxBytes, expiresIn: 300 });
  }),
);
