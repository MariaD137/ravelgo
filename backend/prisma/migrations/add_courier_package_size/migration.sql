-- CreateEnum
CREATE TYPE "PackageSize" AS ENUM ('SMALL', 'MEDIUM', 'LARGE');

-- AlterTable
ALTER TABLE "CourierRequest" ADD COLUMN     "packageSize" "PackageSize" NOT NULL DEFAULT 'MEDIUM';
