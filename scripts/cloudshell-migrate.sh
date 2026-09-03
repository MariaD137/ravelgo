#!/usr/bin/env bash
#
# RavelGo — apply database migrations to the production RDS.
#
# WHY THIS IS SEPARATE: the database lives in PRIVATE_ISOLATED subnets. It has
# no public endpoint, so `prisma migrate deploy` from a normal shell (or a
# default CloudShell) will just hang and time out. You must run from INSIDE the
# VPC.
#
# ONE-TIME SETUP — create a CloudShell **VPC environment**:
#   CloudShell console -> Actions -> "Create VPC environment"
#     VPC:            the RavelGo VPC
#     Subnet:         one of the *egress* subnets  (PRIVATE_WITH_EGRESS)
#                     -> it has NAT, so npm/git/AWS APIs still work, AND it can
#                        route to the isolated DB subnets. Do NOT pick a public
#                        subnet: those have no internet in a VPC environment.
#     Security group: any SG in the VPC (note its id)
#   Then allow that SG into the database:
#     aws ec2 authorize-security-group-ingress \
#       --group-id <RDS_SECURITY_GROUP_ID> --protocol tcp --port 5432 \
#       --source-group <CLOUDSHELL_SG_ID>
#   Remove that rule when you're done migrating.
#
# Then, in that VPC environment (it has its OWN home directory, so set up a
# deploy key there too — see the "authenticate to GitHub" step in
# docs/DEPLOY-RUNBOOK.md; the repo is private and a bare clone will fail):
#   git clone git@github.com:MariaD137/ravelgo.git && cd ravelgo
#   bash scripts/cloudshell-migrate.sh
#
set -euo pipefail
export AWS_PAGER=""

AWS_REGION="${AWS_REGION:-us-east-1}"
ENVNAME="${ENVNAME:-production}"
SUFFIX=""
[[ "$ENVNAME" != "production" ]] && SUFFIX="-$ENVNAME"
DATA_STACK="RavelGo-Data${SUFFIX}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mXX %s\033[0m\n' "$*" >&2; exit 1; }

say "Locating the database secret"
DB_SECRET_ARN="$(aws cloudformation describe-stacks --stack-name "$DATA_STACK" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" --output text)"
[[ -n "$DB_SECRET_ARN" && "$DB_SECRET_ARN" != "None" ]] || die "DatabaseSecretArn not found on $DATA_STACK."

SECRET_JSON="$(aws secretsmanager get-secret-value --region "$AWS_REGION" \
  --secret-id "$DB_SECRET_ARN" --query SecretString --output text)"

DB_HOST="$(node -p "JSON.parse(process.argv[1]).host"     "$SECRET_JSON")"
DB_PORT="$(node -p "JSON.parse(process.argv[1]).port||5432" "$SECRET_JSON")"
DB_USER="$(node -p "JSON.parse(process.argv[1]).username" "$SECRET_JSON")"
DB_PASS="$(node -p "JSON.parse(process.argv[1]).password" "$SECRET_JSON")"
DB_NAME="$(node -p "JSON.parse(process.argv[1]).dbname||'ravelgo'" "$SECRET_JSON")"

echo "host: $DB_HOST"
echo "db:   $DB_NAME   user: $DB_USER"

say "Checking VPC reachability (this is where a non-VPC shell fails)"
if ! timeout 10 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
  warn "Cannot open a TCP connection to $DB_HOST:$DB_PORT."
  warn "Either you are NOT in a CloudShell VPC environment, or the RDS security"
  warn "group does not yet allow inbound 5432 from this environment's security group."
  die  "See the setup notes at the top of this script."
fi
echo "reachable."

# sslmode=require: RDS PostgreSQL 15+ sets rds.force_ssl=1, so a plaintext
# connection is refused outright.
export DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require"

cd "$REPO_ROOT/backend"

say "Installing backend dependencies (needed for the Prisma CLI)"
npm ci

say "Applying migration chain"
npx prisma migrate deploy

say "Verifying the schema landed"
npx prisma migrate status || true

cat <<'EOF'

Expected: "All migrations have been successfully applied." (13 migrations)

Do NOT run the demo seed against production — the seed guard refuses
NODE_ENV=production and any production-looking DATABASE_URL (P0 #14).

Cleanup: remove the temporary RDS security-group ingress rule you added for
this CloudShell environment.
EOF
