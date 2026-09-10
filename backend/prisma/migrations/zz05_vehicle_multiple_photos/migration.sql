-- Vehicles can now carry up to 7 photos instead of a single cover photo.
-- Existing single photoKey (if any) becomes the first entry in photoKeys.
ALTER TABLE "public"."Vehicle" ADD COLUMN "photoKeys" TEXT[] NOT NULL DEFAULT '{}';

UPDATE "public"."Vehicle" SET "photoKeys" = ARRAY["photoKey"] WHERE "photoKey" IS NOT NULL;

ALTER TABLE "public"."Vehicle" DROP COLUMN "photoKey";
