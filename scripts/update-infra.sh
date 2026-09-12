#!/usr/bin/env bash
#
# The recurring "there's a new CDK infra change, apply it to AWS" command —
# run this from CloudShell, from inside your existing clone of this repo.
#
# This is the infra-side counterpart to update-staging.sh (which applies
# Prisma migrations for app-level DB changes). This script instead applies
# changes to the CDK-managed AWS resources themselves — a new resource, a
# changed IAM permission, a new environment variable on the backend service,
# etc. (e.g. the Pinpoint application + push-notification identity pool
# added in infra/lib/auth-stack.ts). Application CODE (the backend image +
# the three web apps) deploys separately via scripts/deploy-staging.sh,
# which never touches infra — this script is the one that does.
#
# Usage (from inside your existing `ravelgo` checkout in CloudShell):
#   bash scripts/update-infra.sh
#
# First-time setup, if you don't already have a checkout: see
# scripts/migrate-staging.sh's own header, or ask Claude to walk you through
# `gh auth login` (browser device-code login, no password/token pasted here).
#
# Requires the AWS CLI + CDK CLI to already have the credentials CloudShell
# provides, and this account to already be CDK-bootstrapped (it is, if
# you've deployed before).
#
# Once you've verified a sender identity in SES and requested production
# access (see docs/DEPLOY-RUNBOOK.md's "SES production access" section — this
# script cannot do either of those for you, they're manual AWS-console/domain
# steps), pass it here to switch Cognito off its 50-email/day default sender:
#   SES_FROM_EMAIL=no-reply@yourdomain.com bash scripts/update-infra.sh
#
set -euo pipefail

ENVNAME="${ENVNAME:-staging}"
# Cognito sends via SES instead of its 50-email/day default sender when this
# is set to a SES-VERIFIED address (P0 #13). Leave unset to make no change.
SES_FROM_EMAIL="${SES_FROM_EMAIL:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }

CTX_ARGS=(--context "envName=$ENVNAME")
if [[ -n "$SES_FROM_EMAIL" ]]; then
  CTX_ARGS+=(--context "sesFromEmail=$SES_FROM_EMAIL")
else
  warn "SES_FROM_EMAIL not set — Cognito stays on its capped default sender."
fi

say "Pulling the latest main"
git fetch origin main
git checkout main
git pull --ff-only origin main

say "Installing CDK dependencies"
cd "$REPO_ROOT/infra"
npm ci

say "Previewing what will change on AWS (environment: $ENVNAME)"
# Read-only — shows the diff against what's currently deployed before
# anything is touched. A clean run with nothing pending prints "no
# differences", which is a valid, expected outcome (nothing to apply).
npx cdk diff --all "${CTX_ARGS[@]}" || true

say "Applying the changes"
npx cdk deploy --all --require-approval broadening "${CTX_ARGS[@]}" \
  --outputs-file /tmp/ravelgo-infra-outputs.json

say "Stack outputs (Pinpoint application id, identity pool id, service URL, etc.)"
cat /tmp/ravelgo-infra-outputs.json 2>/dev/null || warn "No outputs file written — check the deploy output above."

say "Done. Application code deploys separately (bash scripts/deploy-staging.sh, or ask Claude)."
