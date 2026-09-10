-- Admin-user lifecycle: track last authenticated activity for admin accounts.
ALTER TABLE "public"."User" ADD COLUMN "lastLoginAt" TIMESTAMP(3);
