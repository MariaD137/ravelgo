-- Add a driver online/offline presence flag. Drivers are only matched to new
-- trips when they are both approved (status ACTIVE) and online (isOnline true).
ALTER TABLE "Driver" ADD COLUMN "isOnline" BOOLEAN NOT NULL DEFAULT false;
