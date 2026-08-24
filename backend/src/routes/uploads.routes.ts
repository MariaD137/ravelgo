import { PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { requireAuth, requireRole } from "../middleware/auth";
import { s3 } from "../lib/s3";

export const uploadsRouter = Router();

// Only Driver/Admin ever need to write into either bucket today — vehicle
// photos, verification documents, and (for Admin) nothing yet, but never a
// Rider. Kept narrow deliberately; widen only when a real caller needs it.
const UPLOAD_ROLES = ["Driver", "Admin"] as const;

// Per-bucket allowlists. The "documents" bucket accepts scanned/photographed
// paperwork (PDF or photo); "assets" (vehicle photos) is images only — never
// accept application/*, text/*, or anything executable in either.
const ALLOWED_CONTENT_TYPES: Record<"documents" | "assets", readonly string[]> = {
  documents: ["application/pdf", "image/jpeg", "image/png", "image/webp"],
  assets: ["image/jpeg", "image/png", "image/webp"],
};

// A presigned PutObjectCommand can't express a size *range* the way an S3
// POST policy can — but binding `ContentLength` into the signature does
// enforce an exact size: S3 rejects the PUT with SignatureDoesNotMatch if
// the client's actual Content-Length differs. So a client declares its
// file's size up front; anything over the cap is refused before a URL is
// even issued, and the signed URL that *is* issued cannot be used to upload
// more bytes than were declared.
const MAX_BYTES: Record<"documents" | "assets", number> = {
  documents: 10 * 1024 * 1024, // 10MB — scanned documents/photos of paperwork
  assets: 8 * 1024 * 1024, // 8MB — vehicle photos
};

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  fileName: z.string().min(1),
  contentType: z.string().min(1),
  fileSize: z.number().int().positive(),
});

// Driver/Admin: get a short-lived URL to upload a file straight to S3. The
// client PUTs the file bytes to `uploadUrl` (with a matching Content-Length
// header — the signature requires it), then sends `fileKey` back to
// whichever endpoint records the metadata (POST /documents,
// POST /vehicles/:id/photos). Neither of those endpoints trusts an
// arbitrary client-supplied fileKey — they verify it was issued to the
// calling user (see their own ownership checks).
uploadsRouter.post("/uploads/presign", requireAuth, requireRole(...UPLOAD_ROLES), async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { bucket, fileName, contentType, fileSize } = parsed.data;

  if (!ALLOWED_CONTENT_TYPES[bucket].includes(contentType)) {
    return res.status(400).json({
      error: `Unsupported content type for ${bucket}. Allowed: ${ALLOWED_CONTENT_TYPES[bucket].join(", ")}`,
    });
  }
  if (fileSize > MAX_BYTES[bucket]) {
    return res.status(400).json({
      error: `File too large for ${bucket}. Maximum ${Math.floor(MAX_BYTES[bucket] / (1024 * 1024))}MB.`,
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
    ContentLength: fileSize,
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

  res.json({ uploadUrl, fileKey, expiresIn: 300 });
});
