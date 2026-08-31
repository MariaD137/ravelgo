#!/usr/bin/env bash
#
# Publish the RavelGo rider preview (preview/ravelgo-rider.html) to your own
# AWS: uploads it to the CloudFront-fronted assets bucket created by the
# Storage stack, and prints the public https link to share with a client.
# Re-run any time you update the preview — it re-uploads and clears the cache.
#
# Usage:  bash scripts/host-preview.sh
#
set -euo pipefail
export AWS_PAGER=""

ENVNAME=staging
KEY="ravelgo-rider.html"
HTML="$(cd "$(dirname "$0")/.." && pwd)/preview/${KEY}"

if [ ! -f "${HTML}" ]; then echo "ERROR: ${HTML} not found (did you git pull?)"; exit 1; fi

BUCKET="$(aws cloudformation describe-stacks --stack-name "RavelGo-Storage-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text)"
DOMAIN="$(aws cloudformation describe-stacks --stack-name "RavelGo-Storage-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsDistributionDomain'].OutputValue" --output text)"

if [ -z "${BUCKET}" ] || [ "${BUCKET}" = "None" ]; then echo "ERROR: assets bucket not found"; exit 1; fi
if [ -z "${DOMAIN}" ] || [ "${DOMAIN}" = "None" ]; then echo "ERROR: CloudFront domain not found"; exit 1; fi

echo "==> Uploading preview to your assets bucket"
aws s3 cp "${HTML}" "s3://${BUCKET}/${KEY}" \
  --content-type "text/html; charset=utf-8" --cache-control "no-cache" >/dev/null

# Best-effort cache clear so updates appear immediately.
DIST="$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='${DOMAIN}'].Id | [0]" --output text 2>/dev/null || echo "")"
if [ -n "${DIST}" ] && [ "${DIST}" != "None" ]; then
  aws cloudfront create-invalidation --distribution-id "${DIST}" --paths "/${KEY}" >/dev/null 2>&1 || true
fi

echo ""
echo "✅ Your preview is live on your own AWS. Share this link:"
echo ""
echo "   https://${DOMAIN}/${KEY}"
echo ""
