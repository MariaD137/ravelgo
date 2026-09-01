#!/usr/bin/env bash
#
# Build the RavelGo backend container image in AWS CodeBuild and push it to the
# staging ECR repository, so the App Runner service has an image to run.
#
# Why CodeBuild? AWS CloudShell cannot build Docker images (no Docker daemon),
# so we hand the build off to CodeBuild, which builds in the cloud and pushes
# straight to ECR. Nothing is installed locally and no image is built here.
#
# Safe to re-run: it rebuilds from the current backend/ source each time and
# updates the same CodeBuild project. Run it again whenever backend/ changes
# (until GitHub Actions CI is wired up to do it automatically).
#
# Usage:  bash scripts/seed-staging-image.sh
#
set -euo pipefail

ENVNAME=staging
REPO="ravelgo-backend-${ENVNAME}"
PROJECT="ravelgo-image-build-${ENVNAME}"
ROLE="ravelgo-codebuild-${ENVNAME}"

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}"
BUCKET="ravelgo-codebuild-src-${ACCOUNT}-${REGION}"

echo "==> Region:       ${REGION}"
echo "==> Target image: ${ECR_URI}:latest"
echo ""

# --- 1. Source bucket (holds the zipped backend source for CodeBuild) -------
if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "==> Creating source bucket ${BUCKET}"
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null
  fi
fi

# --- 2. Package backend/ and upload (Dockerfile ends up at the zip root) -----
echo "==> Packaging backend source"
SRC_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
rm -f /tmp/ravelgo-src.zip
( cd "${SRC_DIR}" && zip -r -q /tmp/ravelgo-src.zip . \
    -x 'node_modules/*' 'dist/*' 'coverage/*' '.env*' '*.log' )
aws s3 cp /tmp/ravelgo-src.zip "s3://${BUCKET}/ravelgo-src.zip" >/dev/null
echo "==> Source uploaded"

# --- 3. CodeBuild service role (idempotent) ---------------------------------
if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  echo "==> Creating CodeBuild role ${ROLE}"
  aws iam create-role --role-name "${ROLE}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
  echo "==> Waiting for the new role to become usable"
  sleep 15
fi
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

# --- 4. CodeBuild project (create or update) --------------------------------
# The build logs in to ECR, builds the image from the backend source, and
# pushes it. $ECR_URI / $ECR_ACCT come from environmentVariables below;
# $AWS_DEFAULT_REGION is set automatically inside every CodeBuild build.
BUILDSPEC='version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "$ECR_ACCT.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
  build:
    commands:
      - docker build -t "$ECR_URI:latest" .
  post_build:
    commands:
      - docker push "$ECR_URI:latest"
'

cat > /tmp/cb-project.json <<JSON
{
  "name": "${PROJECT}",
  "source": {
    "type": "S3",
    "location": "${BUCKET}/ravelgo-src.zip",
    "buildspec": $(jq -Rs . <<< "${BUILDSPEC}")
  },
  "artifacts": { "type": "NO_ARTIFACTS" },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": true,
    "environmentVariables": [
      { "name": "ECR_URI",  "value": "${ECR_URI}" },
      { "name": "ECR_ACCT", "value": "${ACCOUNT}" }
    ]
  },
  "serviceRole": "${ROLE_ARN}"
}
JSON

if aws codebuild batch-get-projects --names "${PROJECT}" \
     --query 'projects[0].name' --output text 2>/dev/null | grep -q "${PROJECT}"; then
  echo "==> Updating CodeBuild project ${PROJECT}"
  aws codebuild update-project --cli-input-json file:///tmp/cb-project.json >/dev/null
else
  echo "==> Creating CodeBuild project ${PROJECT}"
  aws codebuild create-project --cli-input-json file:///tmp/cb-project.json >/dev/null
fi

# --- 5. Run the build and wait ----------------------------------------------
echo ""
echo "==> Starting the build (builds and pushes the image; usually 3-5 min)"
BUILD_ID="$(aws codebuild start-build --project-name "${PROJECT}" --query 'build.id' --output text)"
echo "==> Build id: ${BUILD_ID}"
echo ""

while true; do
  read -r STATUS PHASE < <(aws codebuild batch-get-builds --ids "${BUILD_ID}" \
    --query 'builds[0].[buildStatus,currentPhase]' --output text)
  if [ "${STATUS}" = "IN_PROGRESS" ]; then
    echo "    ... ${PHASE}"
    sleep 15
  else
    break
  fi
done

echo ""
if [ "${STATUS}" = "SUCCEEDED" ]; then
  echo "✅ Image built and pushed: ${ECR_URI}:latest"
  echo "   The App Runner service can now be switched on."
else
  echo "❌ Build ${STATUS}. Last log lines:"
  read -r GROUP STREAM < <(aws codebuild batch-get-builds --ids "${BUILD_ID}" \
    --query 'builds[0].logs.[groupName,streamName]' --output text)
  aws logs get-log-events --log-group-name "${GROUP}" --log-stream-name "${STREAM}" \
    --limit 60 --query 'events[*].message' --output text 2>/dev/null || true
  exit 1
fi
