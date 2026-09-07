#!/usr/bin/env bash
#
# The recurring "there's a new update, apply it to staging" command — run
# this from CloudShell, from inside your existing clone of this repo.
#
# It pulls the latest `main` (so it always picks up its own latest version
# too, along with any new Prisma migrations), then applies any migrations
# not yet applied to the staging database, via migrate-staging.sh — the
# database has no public endpoint, so this must run from CloudShell (or
# anywhere else with AWS CLI access into the account), not from CI.
#
# Application code (backend + the three web apps) is deployed separately and
# automatically via GitHub Actions whenever a change is pushed to `main` and
# a staging deploy is triggered — this script is only the migration half,
# which that pipeline deliberately cannot do (see staging-deploy.yml's
# check-migrations job).
#
# Usage (from inside your existing `ravelgo` checkout in CloudShell):
#   bash scripts/update-staging.sh
#
# First-time setup, if you don't already have a checkout: see
# scripts/migrate-staging.sh's own header, or ask Claude to walk you through
# `gh auth login` (browser device-code login, no password/token pasted here).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

say "Pulling the latest main"
git fetch origin main
git checkout main
git pull --ff-only origin main

say "Applying any pending staging migrations"
bash scripts/migrate-staging.sh

say "Done. Application code deploys separately (bash scripts/deploy-staging.sh, or ask Claude)."
