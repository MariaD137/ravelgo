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

# App Runner's own Service.Status can report RUNNING (the health check on
# the configured health-check path passed) a few seconds before its edge
# routing has finished cutting every path over to the new instances —
# observed in practice as /health succeeding immediately while every other
# route still 404s for a short window. Retries here, not a longer sleep
# before the first probe, so a genuinely broken deploy still fails fast on
# repeat wrong-status responses rather than only on a timeout.
check() { # <path> <expected HTTP status>
  local code attempt
  for attempt in 1 2 3 4 5; do
    code="$(curl -sS --max-time 20 -o "$RESP" -w '%{http_code}' "$API_URL$1" || echo "000")"
    if [[ "$code" == "$2" ]]; then
      echo "GET $1 -> HTTP $code: $(head -c 600 "$RESP" 2>/dev/null; echo)"
      return 0
    fi
    if [[ "$attempt" -lt 5 ]]; then
      echo "GET $1 -> HTTP $code (expected $2), retrying in 6s (attempt $attempt/5)..."
      sleep 6
    fi
  done
  echo "GET $1 -> HTTP $code: $(head -c 600 "$RESP" 2>/dev/null; echo)"
  echo "::error::GET $1 returned HTTP $code (expected $2) after 5 attempts."
  FAILED=1
}

check /health 200
if grep -q '"paystack":"unconfigured' "$RESP" 2>/dev/null; then
  echo "::warning::Paystack is unconfigured on this backend — card payments, wallet top-ups and payouts will fail until the real secret key is set in Secrets Manager and the service is redeployed (see infra/lib/api-stack.ts)."
fi
check /health/pricing 200
check "/api/pricing/categories?pickupLat=6.5&pickupLng=3.4&distanceKm=1&durationMinutes=5" 401

rm -f "$RESP"
exit "$FAILED"
