-- AlterTable
ALTER TABLE "Driver" ADD COLUMN     "isOnline" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "lastOnlineAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "DriverOnlineSession" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DriverOnlineSession_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DriverOnlineSession_driverId_startedAt_idx" ON "DriverOnlineSession"("driverId", "startedAt");

-- AddForeignKey
ALTER TABLE "DriverOnlineSession" ADD CONSTRAINT "DriverOnlineSession_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Partial unique index: at most one OPEN session (endedAt IS NULL) per
-- driver. Not expressible in schema.prisma's DSL, so it's hand-added here.
-- This is the DB-level backstop for src/services/presence.ts's
-- transaction — a concurrent double "go online" call race can only ever
-- leave one open row, the second write fails and the route treats that as
-- "already online" instead of creating a duplicate open session.
CREATE UNIQUE INDEX "DriverOnlineSession_one_open_per_driver"
  ON "DriverOnlineSession" ("driverId")
  WHERE "endedAt" IS NULL;
