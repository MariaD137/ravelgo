#!/usr/bin/env bash
# Apply Prisma migrations to the PRODUCTION RDS database. See migrate-env.sh
# for how this actually works (a CodeBuild job inside the VPC, since the DB
# has no public endpoint) — it will ask for an explicit confirmation before
# touching production.
#
# Usage:  bash scripts/migrate-production.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/migrate-env.sh" production
