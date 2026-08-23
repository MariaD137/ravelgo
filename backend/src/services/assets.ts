import { env } from "../config/env";

/**
 * Turns an S3 object key (minted by POST /uploads/presign, e.g.
 * "<cognitoSub>/<uuid>-photo.jpg") into a URL a client can actually load.
 *
 * If ASSETS_PUBLIC_BASE_URL is configured (the CloudFront domain in front
 * of the assets bucket — see infra/lib/storage-stack.ts), the key is
 * resolved against it. Until that's deployed, this returns the bare key
 * unchanged rather than inventing a URL that would 404 — callers that store
 * the result (e.g. vehicles.routes.ts) end up with a value that is honestly
 * "not resolvable yet," not a fake-looking working link.
 */
export function resolveAssetUrl(key: string): string {
  if (!env.ASSETS_PUBLIC_BASE_URL) return key;
  return `${env.ASSETS_PUBLIC_BASE_URL.replace(/\/+$/, "")}/${key}`;
}
