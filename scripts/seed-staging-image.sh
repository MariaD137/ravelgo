#!/usr/bin/env bash
# Thin wrapper kept for back-compat: builds and pushes the staging backend
# image. See scripts/seed-backend-image.sh for the generalized version (also
# used for production) and the full explanation of why this step exists.
set -euo pipefail
exec "$(dirname "$0")/seed-backend-image.sh" staging
