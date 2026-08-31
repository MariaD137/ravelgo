#!/usr/bin/env bash
#
# Build the RavelGo apps for the WEB and publish them to your own AWS, so each
# can be opened as a link in any browser — no downloads, no installs.
#
# CloudShell can't build Flutter, so this hands each build to CodeBuild: it
# installs Flutter, builds the web app, uploads it to the CloudFront-fronted
# assets bucket under its own path, clears the cache, and prints the link.
#
# Builds all three apps by default. To build just one:
#   bash scripts/host-web-staging.sh rider     # or: driver | admin
#
set -euo pipefail
export AWS_PAGER=""

ENVNAME=staging
PROJECT="ravelgo-web-${ENVNAME}"
ROLE="ravelgo-web-${ENVNAME}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
SRC_BUCKET="ravelgo-codebuild-src-${ACCOUNT}-${REGION}"

# app-dir : url-path : friendly label
APPS=( "user_app:rider-web:Rider app" "driver_app:driver-web:Driver app" "admin_app:admin-web:Admin app" )
FILTER="${1:-all}"

# Your Google Maps browser key, passed in from your shell (never stored here):
#   export GOOGLE_MAPS_API_KEY=AIza...   then run this script.
# It's injected into the web build's .env and index.html. It's fine for this key
# to ship in the web app — it's public by design and restricted to your
# CloudFront domain in the Google console. If unset, the apps build fine but
# maps render blank.
GMK="${GOOGLE_MAPS_API_KEY:-}"
if [ -z "${GMK}" ]; then
  echo "NOTE: GOOGLE_MAPS_API_KEY is not set — maps will render blank."
  echo "      To enable maps: export GOOGLE_MAPS_API_KEY=AIza... then re-run."
fi

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

echo "==> Reading backend + Cognito config from your deployed stacks"
API_URL="$(aws cloudformation describe-stacks --stack-name "RavelGo-Api-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ServiceUrl'].OutputValue" --output text 2>/dev/null || echo "")"
POOL_ID="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text 2>/dev/null || echo "")"
CLIENT_ID="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")"
echo "    Cognito pool:  ${POOL_ID:-<none>}"

echo "==> Ensuring source bucket + CodeBuild role"
aws s3api head-bucket --bucket "${SRC_BUCKET}" >/dev/null 2>&1 || aws s3 mb "s3://${SRC_BUCKET}" >/dev/null
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

# Flutter web build; $WEB_PATH decides which folder/link this app lives at.
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
      - printf "GOOGLE_MAPS_API_KEY=%s\nAPI_BASE_URL=%s\nCOGNITO_USER_POOL_ID=%s\nCOGNITO_CLIENT_ID=%s\nAWS_REGION=%s\n" "$GOOGLE_MAPS_API_KEY" "$API_BASE_URL" "$COGNITO_USER_POOL_ID" "$COGNITO_CLIENT_ID" "$AWS_DEFAULT_REGION" > .env
      - flutter config --enable-web
      - flutter create --platforms=web .
      # Inject the Google Maps JS SDK into the page so google_maps_flutter can
      # render tiles on the web. Skipped when no key is provided.
      - if [ -n "$GOOGLE_MAPS_API_KEY" ]; then sed -i "s#</head>#  <script src=\"https://maps.googleapis.com/maps/api/js?key=$GOOGLE_MAPS_API_KEY\"></script>\n  </head>#" web/index.html; fi
      - flutter pub get
      - echo "Building web app for /$WEB_PATH/"
      - flutter build web --release --base-href "/$WEB_PATH/"
      - aws s3 sync build/web "s3://$ASSETS_BUCKET/$WEB_PATH/" --delete
  post_build:
    commands:
      - aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/$WEB_PATH/*" || true
'

RESULTS=()
for entry in "${APPS[@]}"; do
  IFS=: read -r APPDIR WEBPATH LABEL <<< "${entry}"
  case "${FILTER}" in
    all) ;;
    rider)  [ "${APPDIR}" = "user_app" ]   || continue ;;
    driver) [ "${APPDIR}" = "driver_app" ] || continue ;;
    admin)  [ "${APPDIR}" = "admin_app" ]  || continue ;;
    *) echo "Unknown app '${FILTER}' (use: rider | driver | admin)"; exit 1 ;;
  esac

  echo ""
  echo "=================================================================="
  echo "==> ${LABEL}  ->  /${WEBPATH}/"
  echo "=================================================================="
  SRC_DIR="$(cd "$(dirname "$0")/../${APPDIR}" && pwd)"
  ZIP="ravelgo-web-${APPDIR}.zip"
  rm -f "/tmp/${ZIP}"
  ( cd "${SRC_DIR}" && zip -r -q "/tmp/${ZIP}" . \
      -x 'build/*' '.dart_tool/*' '.env' '*/.gradle/*' 'android/.gradle/*' 'ios/*' '*.log' )
  aws s3 cp "/tmp/${ZIP}" "s3://${SRC_BUCKET}/${ZIP}" >/dev/null

  cat > /tmp/cb-web.json <<JSON
{
  "name": "${PROJECT}",
  "source": { "type": "S3", "location": "${SRC_BUCKET}/${ZIP}", "buildspec": $(jq -Rs . <<< "${BUILDSPEC}") },
  "artifacts": { "type": "NO_ARTIFACTS" },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_MEDIUM",
    "environmentVariables": [
      { "name": "ASSETS_BUCKET", "value": "${ASSETS_BUCKET}" },
      { "name": "DIST_ID", "value": "${DIST_ID}" },
      { "name": "WEB_PATH", "value": "${WEBPATH}" },
      { "name": "API_BASE_URL", "value": "${API_URL}" },
      { "name": "COGNITO_USER_POOL_ID", "value": "${POOL_ID}" },
      { "name": "COGNITO_CLIENT_ID", "value": "${CLIENT_ID}" },
      { "name": "GOOGLE_MAPS_API_KEY", "value": "${GMK}" }
    ]
  },
  "serviceRole": "${ROLE_ARN}"
}
JSON

  if aws codebuild batch-get-projects --names "${PROJECT}" \
       --query 'projects[0].name' --output text 2>/dev/null | grep -q "${PROJECT}"; then
    aws codebuild update-project --cli-input-json file:///tmp/cb-web.json >/dev/null
  else
    aws codebuild create-project --cli-input-json file:///tmp/cb-web.json >/dev/null
  fi

  echo "==> Building (installs Flutter + builds; ~6-10 min)"
  BID="$(aws codebuild start-build --project-name "${PROJECT}" --query 'build.id' --output text)"
  while true; do
    ST="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].buildStatus' --output text)"
    PH="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].currentPhase' --output text)"
    [ "${ST}" = "IN_PROGRESS" ] && { echo "    ... ${PH}"; sleep 20; continue; }
    break
  done
  echo "==> ${LABEL}: ${ST}"
  if [ "${ST}" = "SUCCEEDED" ]; then
    RESULTS+=( "✅ ${LABEL}:  https://${DOMAIN}/${WEBPATH}/index.html" )
  else
    RESULTS+=( "❌ ${LABEL}:  build ${ST} (see logs below)" )
    read -r GRP STRM < <(aws codebuild batch-get-builds --ids "${BID}" \
      --query 'builds[0].logs.[groupName,streamName]' --output text)
    echo "----- ${LABEL} last log lines -----"
    aws logs get-log-events --log-group-name "${GRP}" --log-stream-name "${STRM}" \
      --limit 400 --query 'events[*].message' --output text 2>/dev/null | tail -40
    echo "-----------------------------------"
  fi
done

echo ""
echo "=================== YOUR APP LINKS ==================="
for r in "${RESULTS[@]}"; do echo "  ${r}"; done
echo "====================================================="
