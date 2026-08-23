-- Adds an optional, resolved image URL to Vehicle. Nullable, no default —
-- every existing row keeps NULL (renders as "no vehicle photo" in the
-- Flutter apps), nothing is backfilled or guessed.
ALTER TABLE "Vehicle" ADD COLUMN "imageUrl" TEXT;
