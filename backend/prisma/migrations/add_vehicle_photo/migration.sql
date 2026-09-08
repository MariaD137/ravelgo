-- Vehicle photo capture (DA-1): S3 key in the public assets bucket.
ALTER TABLE "public"."Vehicle" ADD COLUMN "photoKey" TEXT;
