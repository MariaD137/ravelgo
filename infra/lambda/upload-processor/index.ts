import {
  DeleteObjectCommand,
  GetObjectCommand,
  GetObjectTaggingCommand,
  PutObjectCommand,
  PutObjectTaggingCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { fileTypeFromBuffer } from "file-type";
import ExifTransformer from "exif-be-gone";
import type { Readable } from "node:stream";

const s3 = new S3Client({});

const DOCUMENTS_BUCKET = process.env.DOCUMENTS_BUCKET_NAME ?? "";
const ASSETS_BUCKET = process.env.ASSETS_BUCKET_NAME ?? "";

// The presigned-upload endpoint (backend/src/routes/uploads.routes.ts) only
// constrains the client-declared Content-Type header — a client can still
// upload arbitrary bytes under a false Content-Type. This is the backstop:
// inspect the real magic bytes after the object lands in S3, independent of
// whatever the uploader claimed.
const ALLOWED_MIME_BY_BUCKET: Record<string, ReadonlySet<string>> = {
  [DOCUMENTS_BUCKET]: new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]),
  [ASSETS_BUCKET]: new Set(["image/jpeg", "image/png", "image/webp"]),
};

// exif-be-gone strips EXIF/XMP/FLIR (jpeg, tiff) and text/timestamp chunks
// (png) that can carry GPS coordinates and other metadata a rider or driver
// never intended to publish — most relevant for AssetsBucket, which serves
// straight to the public internet via CloudFront.
const STRIPPABLE_MIME = new Set(["image/jpeg", "image/png"]);

const VALIDATION_TAG_KEY = "UploadValidation";
const VALIDATION_TAG_VALUE = "passed";

interface S3ObjectCreatedEvent {
  detail: {
    bucket: { name: string };
    object: { key: string };
  };
}

async function streamToBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function stripExif(input: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const transformer = new ExifTransformer();
    const chunks: Buffer[] = [];
    transformer.on("data", (chunk: Buffer) => chunks.push(chunk));
    transformer.on("end", () => resolve(Buffer.concat(chunks)));
    transformer.on("error", reject);
    transformer.end(input);
  });
}

async function alreadyValidated(bucket: string, key: string): Promise<boolean> {
  const { TagSet } = await s3.send(new GetObjectTaggingCommand({ Bucket: bucket, Key: key }));
  return (TagSet ?? []).some((tag) => tag.Key === VALIDATION_TAG_KEY && tag.Value === VALIDATION_TAG_VALUE);
}

// Rewriting a strippable object's bytes (below) is itself a PutObject, which
// fires another "Object Created" event and re-invokes this same function.
// Checking for our own tag first — and setting it atomically as part of the
// rewrite's PutObject call, not as a separate follow-up call — is what stops
// that from looping: the re-invocation sees the tag already there and
// returns immediately instead of stripping and re-uploading again.
export const handler = async (event: S3ObjectCreatedEvent): Promise<void> => {
  const bucket = event.detail.bucket.name;
  const key = event.detail.object.key;

  const allowed = ALLOWED_MIME_BY_BUCKET[bucket];
  if (!allowed) {
    console.error(`Ignoring object-created event for unrecognized bucket: ${bucket}`);
    return;
  }

  if (await alreadyValidated(bucket, key)) {
    return;
  }

  const getResult = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const body = await streamToBuffer(getResult.Body as Readable);

  const detected = await fileTypeFromBuffer(body);
  const detectedMime = detected?.mime;

  if (!detectedMime || !allowed.has(detectedMime)) {
    console.warn(
      `Rejecting s3://${bucket}/${key}: uploaded bytes don't match an allowed signature ` +
        `(detected: ${detectedMime ?? "unrecognized"})`,
    );
    // Delete the exact version, not just the current one, so a versioned
    // bucket (DocumentsBucket) doesn't leave the rejected bytes recoverable
    // in a prior version behind a delete marker.
    await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key, VersionId: getResult.VersionId }));
    return;
  }

  if (!STRIPPABLE_MIME.has(detectedMime)) {
    await s3.send(
      new PutObjectTaggingCommand({
        Bucket: bucket,
        Key: key,
        Tagging: { TagSet: [{ Key: VALIDATION_TAG_KEY, Value: VALIDATION_TAG_VALUE }] },
      }),
    );
    return;
  }

  const cleaned = await stripExif(body);
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: cleaned,
      ContentType: detectedMime,
      Tagging: `${VALIDATION_TAG_KEY}=${VALIDATION_TAG_VALUE}`,
    }),
  );
};
