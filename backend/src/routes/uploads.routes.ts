import { S3Client } from "@aws-sdk/client-s3";
import { createPresignedPost } from "@aws-sdk/s3-presigned-post";
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

// Generous enough for a phone-camera photo or a scanned multi-page PDF,
// bounded enough that a client can't drive S3 storage/transfer costs by
// uploading arbitrarily large objects.
const MAX_UPLOAD_BYTES = 15 * 1024 * 1024;

const presignSchema = z.object({
  bucket: z.enum(["documents", "assets"]),
  fileName: z.string().min(1).max(200),
  contentType: z.enum(ALLOWED_CONTENT_TYPES as [string, ...string[]]),
});

// Strips everything but the file's own basename and extension so the
// user-controlled part of an S3 key can never carry a path separator,
// control character, or leading dot — matches only what's needed to keep
// the object's original name recognizable to the uploader.
function sanitizeFileName(rawName: string): string {
  const base = rawName.split(/[/\\]/).pop() ?? rawName;
  const cleaned = base.replace(/[^a-zA-Z0-9._-]/g, "_").replace(/^\.+/, "");
  return cleaned.length > 0 ? cleaned.slice(0, 150) : "file";
}

// Any authenticated user: get short-lived, size-capped POST-form credentials
// to upload a file straight to S3 (client posts the returned `url` + `fields`
// as multipart/form-data with the file itself as the last field), then sends
// `fileKey` back to whichever endpoint records the metadata (e.g. POST
// /documents). A presigned PutObjectCommand can't express a max size — S3
// only accepts an exact ContentLength, not a range — so this uses
// createPresignedPost's content-length-range condition instead, which does.
uploadsRouter.post("/uploads/presign", requireAuth, async (req, res) => {
  const parsed = presignSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const bucketName = parsed.data.bucket === "documents" ? env.DOCUMENTS_BUCKET : env.ASSETS_BUCKET;
  if (!bucketName) {
    return res.status(500).json({ error: `${parsed.data.bucket} bucket is not configured` });
  }

  const fileKey = `${req.user!.sub}/${randomUUID()}-${sanitizeFileName(parsed.data.fileName)}`;

  const { url, fields } = await createPresignedPost(s3, {
    Bucket: bucketName,
    Key: fileKey,
    Conditions: [
      ["content-length-range", 0, MAX_UPLOAD_BYTES],
      ["eq", "$Content-Type", parsed.data.contentType],
    ],
    Fields: {
      "Content-Type": parsed.data.contentType,
    },
    Expires: 300,
  });

  res.json({ url, fields, fileKey, expiresIn: 300, maxUploadBytes: MAX_UPLOAD_BYTES });
});
