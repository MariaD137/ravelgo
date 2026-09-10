#!/usr/bin/env bash
# Apply Prisma migrations to the staging RDS database. See migrate-env.sh for
# how this actually works (a CodeBuild job inside the VPC, since the DB has
# no public endpoint).
#
# Usage:  bash scripts/migrate-staging.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/migrate-env.sh" staging
