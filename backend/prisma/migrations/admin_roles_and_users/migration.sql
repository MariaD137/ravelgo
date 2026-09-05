-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('SUPER_ADMIN', 'OPERATIONS_MANAGER', 'SUPPORT_AGENT', 'FINANCE_VIEWER');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "adminRole" "AdminRole";
