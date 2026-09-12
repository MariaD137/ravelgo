-- Additive: optional free-text feedback a rider can leave alongside their
-- 1-5 star rating (POST /trips/:id/rating already accepted `comment` in its
-- request schema but silently discarded it — this stores what it accepts).
ALTER TABLE "Trip" ADD COLUMN "riderComment" TEXT;
