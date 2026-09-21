-- AlterTable
ALTER TABLE "CarPaddyRequest" ADD COLUMN     "fileKey" TEXT,
ADD COLUMN     "rejectionReason" TEXT,
ADD COLUMN     "renewalDate" TIMESTAMP(3);
