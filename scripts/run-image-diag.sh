#!/usr/bin/env bash
#
# Diagnostic: run the already-built staging backend image inside CodeBuild
# (which reliably captures container stdout/stderr, unlike App Runner's VPC
# log wiring) and print ~15 seconds of its startup output. Dummy env values
# are supplied so config validation passes; the DB host is bogus, so the app
# will start and log "listening on port 8080" if the image is healthy, or
# print a crash/stack trace if something dies at startup. It never connects
# to the real database — this only answers "does the container boot?".
#
# Usage:  bash scripts/run-image-diag.sh
#
set -euo pipefail

ENVNAME=staging
PROJECT="ravelgo-image-build-${ENVNAME}"   # reuse the existing build project
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

BUILDSPEC='version: 0.2
phases:
  build:
    commands:
      - aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "$ECR_ACCT.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
      - docker pull "$ECR_URI:latest"
      - echo "=====CONTAINER-STARTUP-BELOW====="
      - timeout 15 docker run --rm -e NODE_ENV=production -e COGNITO_USER_POOL_ID=us-east-1_diag -e COGNITO_CLIENT_ID=diagclient -e DB_HOST=127.0.0.1 -e DB_PORT=5432 -e DB_NAME=ravelgo -e DB_USERNAME=diag -e DB_PASSWORD=diag -e ALLOWED_ORIGINS=https://example.com -e STRIPE_SECRET_KEY=sk_test_diag -e STRIPE_WEBHOOK_SECRET=whsec_diag "$ECR_URI:latest" || true
      - echo "=====CONTAINER-STARTUP-ABOVE====="
'

echo "==> Starting diagnostic build (pull image, run it, capture startup)"
BID="$(aws codebuild start-build --project-name "${PROJECT}" \
  --buildspec-override "${BUILDSPEC}" --query 'build.id' --output text)"
echo "==> Build id: ${BID}"

while true; do
  ST="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].buildStatus' --output text)"
  [ "${ST}" = "IN_PROGRESS" ] && { echo "    ... running"; sleep 12; continue; }
  break
done
echo "==> Build status: ${ST}"
echo ""
echo "================= CONTAINER STARTUP OUTPUT ================="
read -r GRP STRM < <(aws codebuild batch-get-builds --ids "${BID}" \
  --query 'builds[0].logs.[groupName,streamName]' --output text)
aws logs get-log-events --log-group-name "${GRP}" --log-stream-name "${STRM}" \
  --limit 300 --query 'events[*].message' --output text 2>/dev/null \
  | sed -n '/CONTAINER-STARTUP-BELOW/,/CONTAINER-STARTUP-ABOVE/p'
echo "==========================================================="
