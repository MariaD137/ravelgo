#!/usr/bin/env bash
#
# RavelGo — deploy to AWS from AWS CloudShell.
#
# Run this INSIDE AWS CloudShell (it uses your console session's credentials).
# Phases are explicit and idempotent — run them in order, checking output as you
# go. This is a production deploy: nothing here runs automatically end-to-end.
#
#   bash scripts/cloudshell-deploy.sh preflight
#   bash scripts/cloudshell-deploy.sh infra-base     # VPC/RDS/Cognito/ECR, no service
#   bash scripts/cloudshell-deploy.sh secrets        # overwrite Paystack/Maps placeholders
#   bash scripts/cloudshell-deploy.sh image          # docker build + push to ECR
#   bash scripts/cloudshell-deploy.sh service        # bring up App Runner
#   bash scripts/cloudshell-deploy.sh outputs        # print everything you need
#
# Then run migrations from a CloudShell **VPC environment**:
#   bash scripts/cloudshell-migrate.sh
#
set -euo pipefail

export AWS_PAGER=""

# ---- configuration (override by exporting before running) -------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVNAME="${ENVNAME:-production}"
# Cognito sends via SES when this is set to a VERIFIED sender (P0 #13).
SES_FROM_EMAIL="${SES_FROM_EMAIL:-}"
# Comma-separated browser origins allowed to call the API (CORS). Required in
# production — the backend refuses to boot with an empty list.
ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

SUFFIX=""
[[ "$ENVNAME" != "production" ]] && SUFFIX="-$ENVNAME"
API_STACK="RavelGo-Api${SUFFIX}"
AUTH_STACK="RavelGo-Auth${SUFFIX}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mXX %s\033[0m\n' "$*" >&2; exit 1; }

ctx_args() {
  local args=(-c "envName=$ENVNAME")
  [[ -n "$SES_FROM_EMAIL" ]]  && args+=(-c "sesFromEmail=$SES_FROM_EMAIL")
  [[ -n "$ALLOWED_ORIGINS" ]] && args+=(-c "allowedOrigins=$ALLOWED_ORIGINS")
  [[ -n "$ALERT_EMAIL" ]]     && args+=(-c "alertEmail=$ALERT_EMAIL")
  printf '%s\n' "${args[@]}"
}

stack_output() { # stack, outputKey
  aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text 2>/dev/null
}

# ---------------------------------------------------------------- preflight --
phase_preflight() {
  say "Identity"
  aws sts get-caller-identity --output table \
    || die "No AWS credentials. Are you in CloudShell (or is your CLI configured)?"

  say "Region / Docker availability"
  echo "Region: $AWS_REGION   Environment: $ENVNAME   Stacks suffix: '${SUFFIX:-<none>}'"
  # CloudShell supports Docker only in these Regions. The image build (phase
  # 'image') needs it; everything else works anywhere.
  local docker_regions="us-east-1 us-east-2 us-west-2 ap-south-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ca-central-1 eu-central-1 eu-west-1 eu-west-2 eu-west-3 sa-east-1"
  if [[ " $docker_regions " != *" $AWS_REGION "* ]]; then
    warn "CloudShell does NOT provide Docker in $AWS_REGION."
    warn "Run the 'image' phase from a Docker-capable Region (e.g. us-east-1) or build it elsewhere."
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "docker: available"
  else
    warn "docker not usable here — the 'image' phase will fail in this shell."
  fi

  say "Tooling"
  node --version || die "Node.js missing"
  local major; major="$(node -p 'process.versions.node.split(".")[0]')"
  (( major >= 18 )) || die "Node >= 18 required for CDK (found $major)"
  npm --version >/dev/null || die "npm missing"
  git --version >/dev/null || die "git missing"

  say "Disk (CloudShell home is limited to 1 GB — we build under /tmp)"
  df -h "$REPO_ROOT" | tail -1

  say "Required configuration"
  [[ -n "$ALLOWED_ORIGINS" ]] || warn "ALLOWED_ORIGINS is empty — the backend REFUSES to boot in production without it. Export it before 'infra-base'."
  [[ -n "$SES_FROM_EMAIL" ]]  || warn "SES_FROM_EMAIL unset — Cognito will use its default low-volume sender (P0 #13 not active)."
  echo
  echo "If the above looks right, continue with: bash scripts/cloudshell-deploy.sh infra-base"
}

# -------------------------------------------------------------- infra-base --
# Everything EXCEPT the App Runner service. The service can't start before an
# image exists in ECR, and this stack is what creates the ECR repo — hence the
# two-phase bootstrap (-c deployService=false).
phase_infra_base() {
  [[ -n "$ALLOWED_ORIGINS" ]] || die "Export ALLOWED_ORIGINS first (comma-separated https origins)."
  cd "$REPO_ROOT/infra"

  say "Installing CDK dependencies"
  npm ci

  say "Bootstrapping CDK (no-op if already bootstrapped)"
  local acct; acct="$(aws sts get-caller-identity --query Account --output text)"
  npx cdk bootstrap "aws://$acct/$AWS_REGION"

  say "Deploying base infrastructure (RDS takes 10-15 min — this is normal)"
  mapfile -t CTX < <(ctx_args)
  npx cdk deploy --all --require-approval broadening \
    -c deployService=false "${CTX[@]}"

  say "Done. Next: bash scripts/cloudshell-deploy.sh secrets"
}

# ------------------------------------------------------------------ secrets --
# The stacks lay down placeholder secrets so no real key is ever committed.
# Replace them BEFORE the service serves traffic.
phase_secrets() {
  local paystack_arn maps_arn
  paystack_arn="$(stack_output "$API_STACK" PaystackSecretArn)"
  maps_arn="$(stack_output "$API_STACK" MapsSecretArn)"
  [[ -n "$paystack_arn" && "$paystack_arn" != "None" ]] || die "PaystackSecretArn not found — has 'infra-base' completed?"

  say "Paystack secret key"
  read -rsp "  Paystack SECRET key (sk_live_/sk_test_): " sk; echo
  [[ "$sk" == sk_* ]] || die "That doesn't look like a Paystack secret key; nothing written."
  aws secretsmanager put-secret-value --region "$AWS_REGION" --secret-id "$paystack_arn" \
    --secret-string "$(printf '{"secretKey":"%s"}' "$sk")" >/dev/null
  echo "  stored."

  say "Google Maps SERVER key (backend-only; never shipped to a client)"
  read -rsp "  Maps server key (AIza...): " mk; echo
  if [[ -n "$mk" ]]; then
    aws secretsmanager put-secret-value --region "$AWS_REGION" --secret-id "$maps_arn" \
      --secret-string "$(printf '{"serverKey":"%s"}' "$mk")" >/dev/null
    echo "  stored."
  else
    warn "skipped — the Places/Geocoding proxy will return a clear 5xx until set."
  fi

  say "Next: bash scripts/cloudshell-deploy.sh image"
}

# -------------------------------------------------------------------- image --
phase_image() {
  docker info >/dev/null 2>&1 || die "Docker is not available in this shell/Region."
  local ecr; ecr="$(stack_output "$API_STACK" EcrRepositoryUri)"
  [[ -n "$ecr" && "$ecr" != "None" ]] || die "EcrRepositoryUri not found — has 'infra-base' completed?"

  say "Reclaiming Docker space (CloudShell images share a small disk)"
  docker system prune -af >/dev/null 2>&1 || true

  say "Logging in to ECR"
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "${ecr%%/*}"

  local tag; tag="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
  say "Building image  ($ecr:$tag)"
  docker build -t "$ecr:$tag" -t "$ecr:latest" "$REPO_ROOT/backend"

  say "Pushing"
  docker push "$ecr:$tag"
  docker push "$ecr:latest"

  say "Next: bash scripts/cloudshell-deploy.sh service"
}

# ------------------------------------------------------------------ service --
phase_service() {
  cd "$REPO_ROOT/infra"
  say "Bringing up App Runner (deployService defaults to true)"
  mapfile -t CTX < <(ctx_args)
  npx cdk deploy "$API_STACK" --require-approval broadening "${CTX[@]}"

  local url; url="$(stack_output "$API_STACK" ServiceUrl)"
  say "Service URL: ${url:-<not yet available>}"
  warn "The database has NO TABLES yet. Run migrations before real traffic:"
  echo "     bash scripts/cloudshell-migrate.sh   (from a CloudShell VPC environment)"
}

# ------------------------------------------------------------------ outputs --
phase_outputs() {
  say "Stack outputs"
  for s in "RavelGo-Network${SUFFIX}" "$AUTH_STACK" "RavelGo-Storage${SUFFIX}" \
           "RavelGo-Data${SUFFIX}" "$API_STACK" "RavelGo-Monitoring${SUFFIX}" "RavelGo-CI${SUFFIX}"; do
    local out
    out="$(aws cloudformation describe-stacks --stack-name "$s" --region "$AWS_REGION" \
            --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output text 2>/dev/null)" || continue
    [[ -n "$out" ]] && { printf '\n[%s]\n' "$s"; printf '%s\n' "$out"; }
  done

  cat <<'EOF'

Use these next:
  ServiceUrl                 -> API_BASE_URL in each Flutter app's .env, and a health check
  UserPoolId / ClientId      -> COGNITO_* in each Flutter app's .env
  EcrRepositoryUri           -> GitHub Actions variable ECR_REPOSITORY_URI
  GitHubActionsDeployRoleArn -> GitHub Actions variable AWS_DEPLOY_ROLE_ARN
  EmailSender                -> confirms whether Cognito is on SES (P0 #13) or the default sender
EOF
}

case "${1:-}" in
  preflight)   phase_preflight ;;
  infra-base)  phase_infra_base ;;
  secrets)     phase_secrets ;;
  image)       phase_image ;;
  service)     phase_service ;;
  outputs)     phase_outputs ;;
  *) die "Usage: bash scripts/cloudshell-deploy.sh {preflight|infra-base|secrets|image|service|outputs}" ;;
esac
