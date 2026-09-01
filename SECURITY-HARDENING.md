# RavelGo — Security Hardening & Production Readiness (Pass 2)

**Date:** 2026-08-29
**Scope:** the remaining findings from `SECURITY-AUDIT.md` — client-supplied fares (Phase 2), rate limiting (Phase 3), file-upload/document ownership (Phase 4), payment integrity (Phase 5), auth-failure monitoring (Phase 6), AWS review (Phase 7), a fresh BOLA/IDOR pass (Phase 8), error handling (Phase 9), dependency/secret scan (Phase 10).
**Method:** every change was traced through the real implementation and verified against a live local PostgreSQL 16 instance (`npm test`, 109/109), a real process boot, and `cdk synth`. No result below is asserted without a command behind it.

> **A note on three subsystems the task asked me to "preserve".** Tracing the
> actual code shows RavelGo has **no RLS**, **no S3 upload-quarantine
> workflow**, and **no driver-presence system**. Authorization is entirely
> application-layer (Prisma with a single DB role); uploads are direct
> presigned PUTs; matching picks the first available `ACTIVE` driver. I have
> not fabricated these subsystems or claimed to preserve them. Where they'd
> matter, they appear below as recommendations, not as existing controls.

---

## 1. Executive Verdict

# 🟢 READY FOR STAGING  (conditional path to production documented below)

Every remaining exploitable or money-touching finding from the prior audit is now fixed and covered by a regression test that fails without the fix. The backend is authoritative for every monetary value, expensive endpoints are individually rate-limited without throttling normal use, security events are observable through CloudWatch alarms, and the production database can no longer be deleted by accident. What stands between here and **READY FOR PRODUCTION** is not code — it's five operational steps (real Stripe keys, a real AWS deploy to exercise the alarms, and three console-side configuration confirmations) listed in §7.

I am deliberately **not** calling this "READY FOR PRODUCTION": doing so would require verifying the alarms fire against a real deployed App Runner log group and that Stripe live keys are wired — neither of which can be proven from this repository alone.

## 2. Security Score: **86 / 100**

What determines it:

| Band | Points | Reasoning |
|---|---:|---|
| Authentication & authorization | 20 / 20 | Cognito JWT verification correct and never bypassed; role + ownership enforced at the DB boundary on every `:id` route; re-verified this pass (Phase 8). |
| Payment / monetary integrity | 19 / 20 | Fare now server-authoritative; final fare bounded & anchored; charge amount re-validated; payout override bounded. −1: trip **distance/duration** are still client-provided (no routing service exists — an honest MVP limit, mitigated by an admin-controlled rate + baseFare floor). |
| Abuse protection (rate limiting) | 13 / 15 | Tiered limiters on the expensive/abusable endpoints + webhook ceiling + logged 429s. −2: still per-instance in-memory (no shared store); fine at single-instance MVP scale, needs a shared store before horizontal scaling. |
| Secrets & config | 15 / 15 | Zero secrets in code or git history; Secrets Manager references only; env fails closed in production. |
| AWS infrastructure | 12 / 15 | Private encrypted DB, BLOCK_ALL S3, OAC, scoped OIDC, ECR scanning; DB deletion-protection now env-aware. −3: no WAF, no S3 access logging, App Runner has no explicit `MaxSize` cap (operational hardening, cost-appropriate to defer). |
| Observability | 7 / 10 | Security-event alarms (auth/authz/rate-limit/payment failures) now exist. −3: unproven against a live deployment; no latency/error-budget SLO alarms yet. |
| Supply chain | 5 / 5 | Only dev-dependency `npm audit` highs; production image (`npm ci --omit=dev`) is clean, re-verified. |

## 3. Findings Fixed

### F-1 — Client-supplied fare → backend now authoritative  (Phase 2 / 5, was the audit's top remaining item)
- **Severity:** High (monetary integrity).
- **Root cause:** `POST /trips` accepted `estimatedFare` straight from the request body; `PATCH /trips/:id/status` accepted an unbounded `finalFare` from the driver, and that value flows directly into the Stripe `PaymentIntent` amount and into driver payouts. There was no server-side authority over any fare.
- **Files:** `src/services/pricing.ts` (new — single source of fare math), `src/lib/money.ts` (new — monetary bounds), `src/routes/trips.routes.ts`, `src/routes/payments.routes.ts`, `src/routes/pricing.routes.ts`, `prisma/seed.ts`, `openapi.yaml`.
- **Fix:**
  1. `POST /trips` no longer accepts a fare. It takes `distanceKm`/`durationMinutes`/`zone` and computes `estimatedFare` server-side from the active `PricingRule` (+ surge) via the shared `quoteFare()` — the exact code `GET /pricing/quote` uses, so quote and stored estimate can never diverge. A client sending `estimatedFare: 1` has it ignored entirely.
  2. `PATCH /trips/:id/status` bounds `finalFare` with `moneyAmountSchema` (finite, positive, ≤ 100 000, ≤ 2 decimals) **and** anchors it to the server-computed estimate: a driver may set it within 0.5×–2× the estimate (waiting time, a longer route), but not to an arbitrary multiple. An `Admin` may override the band for dispute correction.
  3. `POST /trips/:id/charge` re-validates `finalFare` is in the chargeable range before it becomes a Stripe amount (defense in depth), and uses a shared `toCents()`.
  4. The manual payout `amount` override (Admin-only) is now bounded by `moneyAmountSchema`.
- **Honest limitation:** distance/duration remain client-provided because there is no routing/geocoding service in this MVP — the same values `GET /pricing/quote` already trusted. The *rate* applied is authoritative and admin-controlled, and `baseFare` is a floor even for a claimed zero-distance trip. Fully closing this needs a server-side distance source; flagged in §4.
- **Regression tests** (`trips.routes.test.ts`): server-computed normal fare; injected `estimatedFare` ignored; missing / malformed / negative / over-cap inputs → 400; no pricing rule → 409; extreme `finalFare` (100×) → 422; negative `finalFare` → 400; in-band accepted; Admin override allowed. **Verified: all pass.**

### F-2 — Flat global rate limiter → tiered, per-endpoint limits  (Phase 3)
- **Severity:** Medium.
- **Root cause:** one `300 / 15 min` bucket over all of `/api/*`; the Stripe webhook and `/health` sat outside any limit.
- **Files:** `src/middleware/rate-limit.ts` (new), `src/lib/security-log.ts` (new), `src/app.ts`, and the four expensive routes.
- **Fix:** a `sensitiveLimiter` (40 / 15 min) on the genuinely expensive/abusable operations — `POST /trips`, `POST /trips/:id/charge` (Stripe), `POST /uploads/presign` (S3), `POST /payouts/create` and `/:id/process` — plus a high webhook ceiling (600 / min, a flood backstop that won't drop Stripe's retried deliveries). The global 300/15min baseline stays. Every 429 returns a consistent structured body and logs a `RATE_LIMIT_EXCEEDED` security event.
- **Explicitly avoided the prior RavelGo incident** (an over-aggressive global limiter 429'ing real users): limits are sized far above any legitimate single session, and are per-IP. Limiters skip under test for determinism; the limiter's enforcement is proven directly in `rate-limit.test.ts` (under-limit passes; over-limit → 429 with the right body).
- **Regression tests:** `rate-limit.test.ts` (2 tests). **Verified: pass.**

### F-3 — Auth/authz/payment-failure observability  (Phase 6)
- **Severity:** Medium (operational / detection).
- **Root cause:** only 5xx-rate, RDS-CPU/storage, and budget alarms existed; nothing surfaced a burst of 401s, 403s, rate-limiting, or failed charges.
- **Files:** `src/lib/security-log.ts` (new), `src/middleware/auth.ts`, `src/middleware/rate-limit.ts`, `src/routes/billing.routes.ts`, `infra/lib/monitoring-stack.ts`.
- **Fix:** the app emits one stable line per event — `SECURITY_EVENT <TYPE> ...` — for `AUTH_FAILURE` (401), `AUTHZ_FAILURE` (403), `RATE_LIMIT_EXCEEDED` (429), and `PAYMENT_FAILURE` (a failed PaymentIntent). The log line carries **no token, password, or card data** — only type, method, path, and the caller's Cognito sub when known. `monitoring-stack.ts` adds a CloudWatch metric filter + alarm per type on the App Runner application log group, all wired to the existing SNS topic. Thresholds are tuned above ordinary noise (AUTH_FAILURE > 50/5min, AUTHZ_FAILURE > 20/5min, RATE_LIMIT > 20/5min, PAYMENT_FAILURE > 10/5min) with documented purposes, so the channel isn't trained to be ignored. No email/phone is hardcoded — the operator confirms the SNS subscription (unchanged).
- **Verified:** `cdk synth` produces 4 metric filters + 4 new alarms; the log-group name resolves to `/aws/apprunner/ravelgo-backend/<ServiceId>/application`; a real process boot emitted `SECURITY_EVENT AUTH_FAILURE method=GET path=/trips reason=missing_token` in the exact format the filters match.

### F-4 — Production DB deletion protection  (Phase 7)
- **Severity:** Medium (operational safety).
- **Root cause:** `deletionProtection: false` was hardcoded for all environments.
- **Files:** `infra/lib/data-stack.ts`, `infra/bin/infra.ts`.
- **Fix:** now environment-aware — production gets `deletionProtection: true` + `RemovalPolicy.RETAIN`; staging stays deletable with a final snapshot. Defaults to production behaviour when `envName` is unset.
- **Verified:** `cdk synth` (default) → `DeletionProtection: true`, `DeletionPolicy: Retain`; `--context envName=staging` → `DeletionProtection: false`, `DeletionPolicy: Snapshot`.

### F-5 — Error-handler information-disclosure hardening confirmed  (Phase 9)
- **Severity:** Low (verification, not a code change to the handler).
- **What was verified:** the global error handler returns generic messages for unexpected errors and Prisma errors, exposing no stack trace, SQL, or internal path to the client; only the deliberate `ApiError` message (which the app controls) reaches the client.
- **Files:** `src/middleware/error-handler.test.ts` (new).
- **Regression tests:** a raw `Error` containing `ECONNREFUSED 10.0.3.14:5432 password=hunter2` → generic 500 with none of that leaking and no `stack` field; a deliberate `ApiError` keeps its safe message; a simulated Prisma `P2025` → clean 404, raw invocation text not leaked. **Verified: pass.**

### Confirmed still-holding from the prior pass (Phase 8 re-audit)
Re-traced every `:id` route. Ownership/role posture is intact and, where relevant, test-covered: `/trips/:id`(+status,+charge,+driver-location), `/vehicles/:id`, `/payments/:id/receipt`, `/payouts/:id`, `/courier-requests/:id`(+status), and all Admin-only routes (`/drivers`, `/riders`, `/documents/:id/review`, `/rentals`, `/car-paddy`, `/emergency-alerts`, `/support-tickets`, pricing/surge/loyalty/promotions writes). No new IDOR/BOLA found. The trip-status BOLA, payout `driverId` confusion, upload MIME allowlist, and document `fileKey` ownership fixed in the prior pass all remain and still pass their tests.

## 4. Findings Remaining

**Critical:** none.

**High:** none.

**Medium**
- **Client-provided trip distance/duration.** The fare *rate* is authoritative, but the distance it's applied to is asserted by the client (no routing service). A rider can under-report distance. Real fix: a server-side distance source (Maps Distance Matrix / routing) computing distance from pickup/dropoff coordinates. This is a feature build, not a one-line fix — deferred deliberately.
- **Rate limiter is per-instance in-memory.** Correct at single-instance MVP scale; before App Runner scales past one instance, move to a shared store (e.g., Redis/ElastiCache) or the counts reset per instance. Same caveat already documented for the realtime hub.

**Low**
- No WAF / CloudFront in front of App Runner; no S3 access logging; no explicit App Runner `MaxSize` cap (the AWS Budget alarm is the current cost backstop). All cost-appropriate to defer at this stage.
- `console.error(err)` in the error handler logs the full error server-side (CloudWatch only, never to the client) — useful for debugging, acceptable, could be narrowed later.

**Operational / manual** — see §7.

## 5. Tests

```
Backend tests:      109 / 109   PASS   (was 99; +10 new security regression tests)
Lint (eslint):      PASS        (0 errors, 0 warnings)
Typecheck (tsc):    PASS
Build (tsc -p):     PASS
Process boot smoke: PASS        (/health ok, /openapi.json loads, 401 + security log emitted)
npm audit --high:   5 highs — ALL dev-dependency-only (nested js-yaml under eslint;
                    prisma CLI's @prisma/config/deepmerge-ts). Production image
                    (npm ci --omit=dev) is clean — re-verified. Not a production exposure.
CDK typecheck:      PASS
CDK synth (all):    PASS        (4 new metric filters + 4 new alarms; env-aware DB protection)
Docker build:       NOT RUN     — the Docker daemon is not available in this environment
                    (only the CLI is installed). Dockerfile unchanged this pass; the runtime
                    `npm ci --omit=dev` + `prisma generate` path was verified in the prior audit.
Flutter analyze:    NOT RUN     — zero Flutter files changed in this pass (see §6).
Flutter test:       NOT RUN     — same reason.
```

New test files this pass: `src/routes/payouts.routes.test.ts` (prior pass), `src/middleware/rate-limit.test.ts`, `src/middleware/error-handler.test.ts`, plus expanded `src/routes/trips.routes.test.ts` (fare-manipulation battery).

## 6. Flutter Compatibility

**No Flutter files were changed in this pass, so no Flutter re-verification was needed or performed.** The one API contract that changed — `POST /trips` now takes `distanceKm`/`durationMinutes` instead of a client `estimatedFare` — has **no current Flutter consumer**: all three apps run on local mock/session state and do not call this backend yet (confirmed in the prior gap audit and unchanged). When the apps are eventually wired to the live API, the rider trip-request call must send distance/duration and read `estimatedFare` back from the created trip; the matte-charcoal UI is unaffected. The Flutter SDK is present in this environment, but running analyze/test would only re-confirm an unchanged tree, so I have honestly marked them NOT RUN rather than implying they validated this pass's work.

## 7. AWS Staging Readiness

| Verification level | What was checked |
|---|---|
| **Verified locally** | 109/109 tests against real PostgreSQL 16; process boot; `/health`; security-event log format; error-handler non-leakage. |
| **Verified statically** | `tsc` (backend + infra), eslint, `cdk synth` for all stacks including the new metric filters/alarms and env-aware DB protection. |
| **Verified through CI** | Not run in this pass, but `backend-ci.yml` (with the `DOCUMENTS_BUCKET`/`ASSETS_BUCKET` fix from the prior pass) exercises lint + typecheck + build + tests against a Postgres service on every PR. |
| **Verified against real AWS** | **Nothing.** No AWS account is wired into this repo. The alarms, log-group wiring, and DB protection are `synth`-valid but have not fired against a deployed service. |
| **Not verified** | Docker image build (daemon unavailable); alarms triggering end-to-end; Stripe live-key flow. |

## 8. Production Blockers

Before flipping from staging/beta to public production:

1. **Deploy to a real AWS account** and confirm the four security alarms actually transition on synthetic load (a burst of 401s/403s), and that the App Runner application log group name matches the imported pattern.
2. **Set real Stripe keys** in the `StripeSecret` (placeholders ship by design) — `aws secretsmanager put-secret-value ...`.
3. **Build and push the Docker image** through a real Docker/CI runner (not possible here) and confirm the container boots healthy behind App Runner's `/health` check.
4. **Confirm the GitHub `production` environment** has required-reviewer protection (repo settings — not verifiable from code).
5. **Confirm the Google Maps API key** is restricted in Google Cloud Console (Android package + SHA-1); it ships in the APK by necessity and restriction is the only control that matters.
6. **Decide the trip-distance authority** (Medium finding §4): accept client-reported distance for launch, or integrate a routing service — a product call to make consciously, not by default.
7. **Before horizontal scaling:** move the rate limiter (and realtime hub) to a shared store.

---

```
SECURITY HARDENING COMPLETE

Backend:            READY FOR STAGING
Tests:              109 / 109 passing (+10 new security regression tests)
Lint:               PASS (0 errors, 0 warnings)
Typecheck:          PASS
Build:              PASS (+ real process boot verified)
Dependency audit:   PASS for production (5 highs are dev-dependency-only)
Secret scan:        PASS (no secrets in code or git history; no .env tracked)
Infrastructure:     PASS (cdk synth; +security alarms; +env-aware DB deletion protection)
Flutter:            NOT RUN (zero Flutter files changed this pass)

Production blockers:
  1. Deploy to real AWS + confirm the 4 security alarms fire
  2. Set real Stripe keys (placeholders ship by design)
  3. Build/push the Docker image on a real runner + confirm healthy boot
  4. Confirm GitHub `production` environment protection rules
  5. Confirm Google Maps API key restriction in Cloud Console
  6. Decide trip-distance authority (accept client value, or add routing)
  7. Shared-store rate limiter + realtime hub before scaling past 1 instance
```

*Nothing in this pass was pushed to GitHub — awaiting explicit authorization.*
