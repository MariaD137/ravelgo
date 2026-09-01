#!/usr/bin/env bash
#
# Seed the staging RDS database with the data the apps need to work:
#  - an ACTIVE pricing rule (without it, requesting a trip returns 409)
#  - an ACTIVE demo driver (so a rider's booking actually matches a driver)
#  - a little demo data (a completed trip, a funded demo wallet, a ticket)
#
# Like migrate-staging.sh, the database has no public endpoint, so this runs
# `prisma db seed` from a CodeBuild job placed INSIDE the VPC. The seed is safe
# to re-run: the pricing rule/wallet upsert and the demo rows are guarded.
#
# Usage:  bash scripts/seed-staging.sh
#
set -euo pipefail

# Never let the AWS CLI open an interactive pager mid-script.
export AWS_PAGER=""

ENVNAME=staging
PROJECT="ravelgo-seed-${ENVNAME}"
ROLE="ravelgo-migrate-${ENVNAME}"   # reuse the migrate role (same permissions)
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="ravelgo-codebuild-src-${ACCOUNT}-${REGION}"

echo "==> Discovering the private network (VPC, egress subnets, DB-reachable SG)"
VPC_ID="$(aws ec2 describe-vpcs \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=RavelGo-Network-${ENVNAME}" \
  --query 'Vpcs[0].VpcId' --output text)"
mapfile -t SUBNET_ARR < <(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:aws-cdk:subnet-name,Values=egress" \
  --query 'Subnets[].SubnetId' --output text | tr '\t' '\n')
SG_ID="$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=description,Values=App Runner VPC connector to RDS" \
  --query 'SecurityGroups[0].GroupId' --output text)"
DB_SECRET_ARN="$(aws cloudformation describe-stacks --stack-name "RavelGo-Data-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" --output text)"

if [ -z "${VPC_ID}" ] || [ "${VPC_ID}" = "None" ]; then echo "ERROR: VPC not found"; exit 1; fi
if [ -z "${SG_ID}" ] || [ "${SG_ID}" = "None" ]; then echo "ERROR: connector security group not found"; exit 1; fi
if [ "${#SUBNET_ARR[@]}" -eq 0 ]; then echo "ERROR: egress subnets not found"; exit 1; fi
if [ -z "${DB_SECRET_ARN}" ] || [ "${DB_SECRET_ARN}" = "None" ]; then echo "ERROR: DB secret ARN not found"; exit 1; fi

echo "==> Packaging backend source"
SRC_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
rm -f /tmp/ravelgo-src.zip
( cd "${SRC_DIR}" && zip -r -q /tmp/ravelgo-src.zip . -x 'node_modules/*' 'dist/*' 'coverage/*' '.env*' '*.log' )
aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null || aws s3 mb "s3://${BUCKET}" >/dev/null
aws s3 cp /tmp/ravelgo-src.zip "s3://${BUCKET}/ravelgo-src.zip" >/dev/null

if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  echo "ERROR: role ${ROLE} not found. Run scripts/migrate-staging.sh first (it creates the role)."
  exit 1
fi
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

# Build DATABASE_URL from the RDS secret at run time, then run the seed. The
# migrations are applied first so seeding always runs against an up-to-date
# schema.
BUILDSPEC='version: 0.2
phases:
  build:
    commands:
      - echo "Reading DB credentials from Secrets Manager"
      - SECRET=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text)
      - export DATABASE_URL="postgresql://$(echo "$SECRET" | jq -r .username):$(echo "$SECRET" | jq -r .password)@$(echo "$SECRET" | jq -r .host):5432/ravelgo?sslmode=require"
      - echo "Installing dependencies"
      - npm ci
      - echo "Applying migrations"
      - npx prisma migrate deploy
      - echo "Seeding"
      # The seed refuses to run without this explicit opt-in (prisma/seed.ts).
      # It is set here only for the staging seed job; production is never seeded.
      - ALLOW_DEMO_SEED=true npx prisma db seed
'

SUBNET_JSON="$(printf '"%s",' "${SUBNET_ARR[@]}")"; SUBNET_JSON="[${SUBNET_JSON%,}]"

cat > /tmp/cb-seed.json <<JSON
{
  "name": "${PROJECT}",
  "source": { "type": "S3", "location": "${BUCKET}/ravelgo-src.zip", "buildspec": $(jq -Rs . <<< "${BUILDSPEC}") },
  "artifacts": { "type": "NO_ARTIFACTS" },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "environmentVariables": [ { "name": "DB_SECRET_ARN", "value": "${DB_SECRET_ARN}" } ]
  },
  "serviceRole": "${ROLE_ARN}",
  "vpcConfig": { "vpcId": "${VPC_ID}", "subnets": ${SUBNET_JSON}, "securityGroupIds": ["${SG_ID}"] }
}
JSON

if aws codebuild batch-get-projects --names "${PROJECT}" \
     --query 'projects[0].name' --output text 2>/dev/null | grep -q "${PROJECT}"; then
  echo "==> Updating seed project"
  aws codebuild update-project --cli-input-json file:///tmp/cb-seed.json >/dev/null
else
  echo "==> Creating seed project"
  aws codebuild create-project --cli-input-json file:///tmp/cb-seed.json >/dev/null
fi

echo ""
echo "==> Running the seed inside the VPC (usually 1-2 min)"
BID="$(aws codebuild start-build --project-name "${PROJECT}" --query 'build.id' --output text)"
echo "==> Build id: ${BID}"
while true; do
  ST="$(aws codebuild batch-get-builds --ids "${BID}" --query 'builds[0].buildStatus' --output text)"
  [ "${ST}" = "IN_PROGRESS" ] && { echo "    ... running"; sleep 12; continue; }
  break
done
echo ""
echo "==> Result: ${ST}"
read -r GRP STRM < <(aws codebuild batch-get-builds --ids "${BID}" \
  --query 'builds[0].logs.[groupName,streamName]' --output text)
echo "----- seed output (tail) -----"
aws logs get-log-events --log-group-name "${GRP}" --log-stream-name "${STRM}" \
  --limit 300 --query 'events[*].message' --output text 2>/dev/null | tail -40
echo "------------------------------"
if [ "${ST}" = "SUCCEEDED" ]; then
  echo "✅ Seed complete. Pricing is configured and a demo driver is active."
else
  echo "❌ Seed ${ST}. See the output above."
  exit 1
fi
