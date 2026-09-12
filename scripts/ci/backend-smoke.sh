#!/usr/bin/env bash
#
# Prove a freshly deployed backend actually works, not just that it started.
#
#   bash scripts/ci/backend-smoke.sh <api-base-url>
#
# All probes are read-only and unauthenticated:
#   GET /health            200 — database reachable; also reports whether
#                                Paystack is configured (warning if not)
#   GET /health/pricing    200 — the tables GET /api/pricing/categories needs
#                                exist; 503 here means a Prisma migration was
#                                never applied to this environment
#                                (scripts/migrate-<env>.sh)
#   GET /api/pricing/categories  401 — the rider fare endpoint exists (404
#                                would mean a stale image is still serving)
set -euo pipefail

API_URL="${1:?usage: backend-smoke.sh <api-base-url>}"
API_URL="${API_URL%/}"
RESP="$(mktemp)"
FAILED=0

check() { # <path> <expected HTTP status>
  local code
  code="$(curl -sS --max-time 20 -o "$RESP" -w '%{http_code}' "$API_URL$1" || echo "000")"
  echo "GET $1 -> HTTP $code: $(head -c 600 "$RESP" 2>/dev/null; echo)"
  if [[ "$code" != "$2" ]]; then
    echo "::error::GET $1 returned HTTP $code (expected $2)."
    FAILED=1
  fi
}

check /health 200
if grep -q '"paystack":"unconfigured' "$RESP" 2>/dev/null; then
  echo "::warning::Paystack is unconfigured on this backend — card payments, wallet top-ups and payouts will fail until the real secret key is set in Secrets Manager and the service is redeployed (see infra/lib/api-stack.ts)."
fi
check /health/pricing 200
check "/api/pricing/categories?pickupLat=6.5&pickupLng=3.4&distanceKm=1&durationMinutes=5" 401

rm -f "$RESP"
exit "$FAILED"
