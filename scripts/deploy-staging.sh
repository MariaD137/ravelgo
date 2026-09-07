#!/usr/bin/env bash
#
# Trigger the staging deploy — a thin wrapper around the existing
# `.github/workflows/staging-deploy.yml` GitHub Actions workflow (manual-only
# by design; see that file's header). This script does not talk to AWS
# directly and does not replace it — it just saves you a trip to the Actions
# tab. Builds and deploys the backend (App Runner) and all three Flutter web
# apps (admin/driver/rider) from whatever is currently on `main`.
#
# Requires the GitHub CLI (`gh`), authenticated against this repo
# (`gh auth login` once, if you haven't already).
#
# A commit that adds a Prisma migration still needs
#   bash scripts/migrate-staging.sh
# run separately — this script does not apply migrations (same as the
# workflow it triggers; see that workflow's check-migrations job, which only
# warns).
#
# Usage:  bash scripts/deploy-staging.sh
#
set -euo pipefail

REPO="MariaD137/ravelgo"
WORKFLOW="staging-deploy.yml"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mXX %s\033[0m\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) not found — install it: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "Not logged in to gh. Run: gh auth login"

say "Triggering $WORKFLOW on $REPO (branch: main)"
gh workflow run "$WORKFLOW" --repo "$REPO" --ref main

# workflow run is fire-and-forget with no run id in its output, so look up
# the run it just queued (newest workflow_dispatch run for this workflow).
say "Locating the queued run"
RUN_URL=""
for _ in $(seq 1 10); do
  RUN_URL="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch \
              --limit 1 --json url --jq '.[0].url' 2>/dev/null || true)"
  [[ -n "$RUN_URL" ]] && break
  sleep 2
done

if [[ -n "$RUN_URL" ]]; then
  echo "  $RUN_URL"
  say "Streaming status (Ctrl+C any time — the deploy keeps running on GitHub regardless)"
  gh run watch --repo "$REPO" --exit-status "$(basename "$RUN_URL")" || warn "Deploy finished with a non-zero status — check the run above."
else
  warn "Triggered, but couldn't find the run to watch — check the Actions tab: https://github.com/$REPO/actions/workflows/$WORKFLOW"
fi
