#!/usr/bin/env bash
#
# Build the RavelGo rider app for the WEB and publish it to your own AWS, so
# it can be opened as a link in any browser — no downloads, no installs.
#
# CloudShell can't build Flutter, so this hands the build to CodeBuild:
# it installs Flutter, builds the web app, uploads it to the CloudFront-fronted
# assets bucket under /rider-web/, and clears the CloudFront cache. Then it
# prints the public https link. Re-run any time the app changes.
#
# Usage:  bash scripts/host-web-staging.sh
#
set -euo pipefail
export AWS_PAGER=""

ENVNAME=staging
PROJECT="ravelgo-web-${ENVNAME}"
ROLE="ravelgo-web-${ENVNAME}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
SRC_BUCKET="ravelgo-codebuild-src-${ACCOUNT}-${REGION}"

echo "==> Looking up your assets bucket and CloudFront distribution"
ASSETS_BUCKET="$(aws cloudformation describe-stacks --stack-name "RavelGo-Storage-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text)"
DOMAIN="$(aws cloudformation describe-stacks --stack-name "RavelGo-Storage-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsDistributionDomain'].OutputValue" --output text)"
if [ -z "${ASSETS_BUCKET}" ] || [ "${ASSETS_BUCKET}" = "None" ]; then echo "ERROR: assets bucket not found"; exit 1; fi
if [ -z "${DOMAIN}" ] || [ "${DOMAIN}" = "None" ]; then echo "ERROR: CloudFront domain not found"; exit 1; fi
DIST_ID="$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='${DOMAIN}'].Id | [0]" --output text)"

echo "    Assets bucket: ${ASSETS_BUCKET}"
echo "    CloudFront:    ${DOMAIN} (${DIST_ID})"

echo "==> Packaging the rider app source"
SRC_DIR="$(cd "$(dirname "$0")/../user_app" && pwd)"
rm -f /tmp/ravelgo-web-src.zip
( cd "${SRC_DIR}" && zip -r -q /tmp/ravelgo-web-src.zip . \
    -x 'build/*' '.dart_tool/*' '.env' '*/.gradle/*' 'android/.gradle/*' 'ios/*' '*.log' )
aws s3api head-bucket --bucket "${SRC_BUCKET}" >/dev/null 2>&1 || aws s3 mb "s3://${SRC_BUCKET}" >/dev/null
aws s3 cp /tmp/ravelgo-web-src.zip "s3://${SRC_BUCKET}/ravelgo-web-src.zip" >/dev/null

echo "==> Ensuring CodeBuild role"
if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  aws iam create-role --role-name "${ROLE}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess
  echo "==> Waiting for the new role to become usable"
  sleep 15
fi
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

BUILDSPEC='version: 0.2
phases:
  install:
    commands:
      - echo "Installing Flutter (stable)"
      - git clone https://github.com/flutter/flutter.git -b stable --depth 1 /opt/flutter
      - export PATH="$PATH:/opt/flutter/bin"
      - git config --global --add safe.directory /opt/flutter
      - flutter --version
  build:
    commands:
      - export PATH="$PATH:/opt/flutter/bin"
      - cp .env.example .env
      - flutter config --enable-web
      - flutter create --platforms=web .
      - flutter pub get
      - echo "Building web app"
      - flutter build web --release --base-href /rider-web/
      - echo "Publishing to your assets bucket"
      - aws s3 sync build/web "s3://$ASSETS_BUCKET/rider-web/" --delete
  post_build:
    commands:
      - aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/rider-web/*" || true
'

cat > /tmp/cb-web.json <<JSON
{
  "name": "${PROJECT}",
  "source": { "type": "S3", "location": "${SRC_BUCKET}/ravelgo-web-src.zip", "buildspec": $(jq -Rs . <<< "${BUILDSPEC}") },
  "artifacts": { "type": "NO_ARTIFACTS" },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_MEDIUM",
    "environmentVariables": [
      { "name": "ASSETS_BUCKET", "value": "${ASSETS_BUCKET}" },
      { "name": "DIST_ID", "value": "${DIST_ID}" }
    ]
  },
  "serviceRole": "${ROLE_ARN}"
}
JSON

if aws codebuild batch-get-projects --names "${PROJECT}" \
     --query 'projects[0].name' --output text 2>/dev/null | grep -q "${PROJECT}"; then
  echo "==> Updating web build project"
  aws codebuild update-project --cli-input-json file:///tmp/cb-web.json >/dev/null
else
  echo "==> Creating web build project"
  aws codebuild create-project --cli-input-json file:///tmp/cb-web.json >/dev/null
fi

echo ""
echo "==> Building the web app (installs Flutter + builds; ~6-10 min)"
BID="$(aws codebuild start-build --project-name "${PROJECT}" --query 'build.id' --output text)"
echo "==> Build id: ${BID}"
while true; do
  ST="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].buildStatus' --output text)"
  PH="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].currentPhase' --output text)"
  [ "${ST}" = "IN_PROGRESS" ] && { echo "    ... ${PH}"; sleep 20; continue; }
  break
done

echo ""
echo "==> Result: ${ST}"
if [ "${ST}" = "SUCCEEDED" ]; then
  echo ""
  echo "✅ Your rider app is live in the browser. Open / share this link:"
  echo ""
  echo "   https://${DOMAIN}/rider-web/index.html"
  echo ""
else
  echo "❌ Build ${ST}. Last log lines:"
  read -r GRP STRM < <(aws codebuild batch-get-builds --ids "${BID}" \
    --query 'builds[0].logs.[groupName,streamName]' --output text)
  aws logs get-log-events --log-group-name "${GRP}" --log-stream-name "${STRM}" \
    --limit 400 --query 'events[*].message' --output text 2>/dev/null | tail -50
  exit 1
fi
