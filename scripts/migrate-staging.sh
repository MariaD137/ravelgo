#!/usr/bin/env bash
#
# Apply Prisma migrations to the staging RDS database.
#
# The database has no public endpoint (it lives in isolated subnets), so this
# can't run from CloudShell directly. Instead it runs `prisma migrate deploy`
# from a CodeBuild job placed INSIDE the VPC — in the egress subnets, using the
# same security group App Runner uses, which RDS already allows on port 5432.
# The DB credentials are read from Secrets Manager at run time (never stored
# here). Safe to re-run: `migrate deploy` only applies migrations not yet applied.
#
# Usage:  bash scripts/migrate-staging.sh
#
set -euo pipefail

# Never let the AWS CLI open an interactive pager mid-script.
export AWS_PAGER=""

ENVNAME=staging
PROJECT="ravelgo-migrate-${ENVNAME}"
ROLE="ravelgo-migrate-${ENVNAME}"
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

echo "    VPC:     ${VPC_ID}"
echo "    Subnets: ${SUBNET_ARR[*]:-<none>}"
echo "    SG:      ${SG_ID}"

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

echo "==> Ensuring CodeBuild role"
if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  aws iam create-role --role-name "${ROLE}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
  aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
  aws iam put-role-policy --role-name "${ROLE}" --policy-name migrate-secrets-and-vpc \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["secretsmanager:GetSecretValue"],"Resource":"*"},{"Effect":"Allow","Action":["ec2:CreateNetworkInterface","ec2:DescribeNetworkInterfaces","ec2:DeleteNetworkInterface","ec2:DescribeSubnets","ec2:DescribeSecurityGroups","ec2:DescribeDhcpOptions","ec2:DescribeVpcs"],"Resource":"*"},{"Effect":"Allow","Action":"ec2:CreateNetworkInterfacePermission","Resource":"*","Condition":{"StringEquals":{"ec2:AuthorizedService":"codebuild.amazonaws.com"}}}]}'
  echo "==> Waiting for the new role to become usable"
  sleep 15
fi
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

# Build DATABASE_URL from the RDS secret at run time (jq is present in the
# standard CodeBuild image), then apply migrations. A full `npm ci` installs
# the Prisma CLI (a devDependency), which the slim runtime image omits.
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
'

SUBNET_JSON="$(printf '"%s",' "${SUBNET_ARR[@]}")"; SUBNET_JSON="[${SUBNET_JSON%,}]"

cat > /tmp/cb-migrate.json <<JSON
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
  echo "==> Updating migration project"
  aws codebuild update-project --cli-input-json file:///tmp/cb-migrate.json >/dev/null
else
  echo "==> Creating migration project"
  aws codebuild create-project --cli-input-json file:///tmp/cb-migrate.json >/dev/null
fi

echo ""
echo "==> Running migrations inside the VPC (usually 1-2 min)"
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
echo "----- migration output (tail) -----"
aws logs get-log-events --log-group-name "${GRP}" --log-stream-name "${STRM}" \
  --limit 300 --query 'events[*].message' --output text 2>/dev/null | tail -40
echo "-----------------------------------"
if [ "${ST}" = "SUCCEEDED" ]; then
  echo "✅ Migrations applied. Your database now has its tables."
else
  echo "❌ Migration ${ST}. See the output above."
  exit 1
fi
