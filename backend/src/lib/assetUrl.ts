import { env } from "../config/env";

// Vehicle/rental/avatar photos live in the "assets" S3 bucket, fronted by a
// CloudFront distribution that's the only thing ever allowed to read it
// (see infra/lib/storage-stack.ts — BLOCK_ALL public access on the bucket
// itself, Origin Access Control on the distribution). No presigning is
// needed to view one, unlike a private document. Returns null instead of a
// broken URL when the distribution domain isn't configured for this
// environment (e.g. local dev without a deployed CloudFront distribution).
export function publicAssetUrl(fileKey: string): string | null {
  if (!env.ASSETS_CLOUDFRONT_DOMAIN) return null;
  return `https://${env.ASSETS_CLOUDFRONT_DOMAIN}/${fileKey}`;
}
