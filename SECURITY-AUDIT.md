# RavelGo — Security & Hacker-Resistance Audit

**Date:** 2026-08-29
**Scope:** `backend/` (Express + Prisma + PostgreSQL API), `infra/` (AWS CDK), `.github/workflows/`, and the three Flutter apps (`user_app`, `driver_app`, `admin_app`) as consumers of the backend.
**Method:** Full manual trace of every route, every middleware, every CDK stack, and the actual git history — not a scan of which libraries are installed. Every finding below was reproduced against real, running code (a local PostgreSQL 16 instance, `npm test`/`lint`/`typecheck`/`build`, `cdk synth`, and direct `node` scripts), not inferred from reading alone.

---

## Executive Summary

RavelGo's backend is architecturally sound: Cognito JWT verification is correct and never bypassed, the vast majority of endpoints enforce real per-resource ownership (not just role checks), there is zero SQL-injection/SSRF/command-injection surface anywhere in the codebase, secrets are exclusively managed through AWS Secrets Manager references (never plaintext), and the AWS infrastructure (S3 Block Public Access, GitHub OIDC scoped to `repo:MariaD137/ravelgo:ref:refs/heads/main`, least-privilege IAM roles) is genuinely well-built.

Against that foundation, this audit found and fixed three serious defects: **the application could not boot at all** (a YAML syntax error crashed the whole Express process before any route could serve traffic — confirmed by running the real test suite, which was 0/20 passing), **a BOLA + payment-manipulation bug** letting any authenticated Driver alter any trip's status and fare (not just their own), and **a three-way ID-confusion bug** that made the entire driver payout self-service system non-functional and its automatic fare calculation always return zero. All three are now fixed, covered by new regression tests, and re-verified. Two further gaps — no content-type restriction on file uploads, and no ownership check on document `fileKey` — were also fixed.

Two important scoping facts, both confirmed by reading the code (not assumed): **this backend is not currently deployed to any live AWS account** (`infra/README.md`: "nobody's AWS account is wired into this repo"), and **none of the three Flutter apps currently call it** — all three run on local/mock state (per the separate gap-audit report from this repository's prior session). This audit therefore evaluates the backend/infra on its own merits as a pre-launch system, not as something already carrying live user data.

**Overall Security Grade: B** (up from what would have been an F pre-fix, given the boot-blocking defect and the payment-manipulation BOLA). The remaining gap to an A is entirely hardening work appropriate to a pre-launch stage — rate-limit granularity, a couple of missing monitoring alarms, WebSocket token handling — not exploitable vulnerabilities.

---

## Critical Findings

### C-1 — Application fails to boot; entire test suite was failing
- **File:** `backend/openapi.yaml:1615,1617`
- **Was:** `field: { type: string, description: Field name or path (e.g., "email", "address.zipCode") }` — an unquoted YAML flow-scalar containing a bare comma.
- **Why it's critical:** `app.ts:71` parses this file **eagerly, at module load**, to serve `/openapi.json` and Swagger UI. A parse failure throws before Express finishes wiring up, crashing the whole process — not just the docs endpoints. Reproduced: `npm test` was 0/20 test files passing with `YAMLException: missed comma between flow collection entries (1615:107)`.
- **Impact:** if deployed as-is, the App Runner container would crash on startup, the `/health` check would never pass, and the service would never go healthy. Total availability loss.
- **Status: FIXED.** Quoted both description strings. Verified via a standalone `js-yaml` parse (`YAML PARSES OK`) and the full test suite now passing (99/99).

### C-2 — BOLA + payment/price manipulation on the trip lifecycle
- **File:** `backend/src/routes/trips.routes.ts:58` (`PATCH /trips/:id/status`)
- **Vulnerable code (before):**
  ```ts
  tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
    const trip = await prisma.trip.update({ where: { id: req.params.id }, data: { status, finalFare, ... } });
  ```
  No check that the calling driver is the one assigned to `req.params.id`.
- **Exploit:** any authenticated Driver account (not necessarily assigned to the trip) can PATCH any trip by ID — cancel it, mark it COMPLETED, or set `finalFare` to an arbitrary value.
- **Proof this was a real gap, not a design choice:** `courier.routes.ts:79-92` implements the identical feature *correctly* (`if (!isAdmin) { if (!driver || existing.driverId !== driver.id) return 403 }`). The existing test for the vulnerable endpoint (`trips.routes.test.ts`, pre-fix) used a driver with **no relation to the trip** and asserted success — the vulnerability was encoded into the test fixture as "expected."
- **Compounding factor:** `finalFare` set here flows directly into the real Stripe `PaymentIntent` amount at `POST /trips/:id/charge` (`payments.routes.ts:41`). Combined with `POST /trips` taking a client-supplied `estimatedFare` instead of the working `GET /pricing/quote` engine, there was no server-side fare enforcement anywhere in the ride lifecycle.
- **Impact:** cross-driver trip sabotage; fare manipulation on real payment amounts.
- **Severity:** 🔴 Critical (payment integrity + cross-account write access).
- **Status: FIXED.** Added the same ownership check used correctly elsewhere in the codebase. **Test:** existing test updated to assign the calling driver to the trip (proving the happy path); new test `PATCH /api/trips/:id/status rejects a Driver who isn't assigned to the trip` proves the 403 and that trip state is unchanged. Both pass.
- **Not yet fixed (documented, not silently left open):** `estimatedFare` at trip creation is still client-supplied rather than computed from `GET /pricing/quote`. This is a real remaining gap — see High/Remaining Vulnerabilities below; fixing it well means deciding whether the *rider's shown estimate* should always equal the *pricing engine's* quote (a product decision, not purely a security one), so it wasn't changed without that decision being made.

---

## High Findings

### H-1 — Driver payout system: three-way ID confusion (self-service payouts were non-functional)
- **Files:** `backend/src/routes/payouts.routes.ts`, `backend/src/services/payouts.ts`, `prisma/schema.prisma:359-391`
- **The bug:** `Payout.driverId` / `DriverBankAccount.driverId` are FKs to **`User.id`** (confirmed in the schema and the migration SQL's `ADD CONSTRAINT ... REFERENCES "User"("id")`). But:
  - Driver self-service routes keyed everything on `req.user!.sub` — the **Cognito subject**, never equal to `User.id`.
  - `calculatePayoutForPeriod()` queried `Trip.driverId` / `DriverSubscription.driverId` — both FKs to a **third** id, `Driver.id` — using the `User.id` passed from the admin route.
- **Concretely, before the fix:** `POST /payouts/bank-account` always threw a Postgres foreign-key violation. A driver's own `/payouts/history` never showed a payout an admin created for them. `calculatePayoutForPeriod` always returned 0 trips / $0, pushing every admin toward the unchecked manual `amount` override with no automatic verification against real completed trips.
- **Corroborating evidence:** `payouts.routes.ts` was the **only** one of 19 route files with no `.test.ts` companion, and the only file failing `npm run lint` (10 `no-explicit-any` errors) — every available signal pointed at this being the least-reviewed module in the repo.
- **Severity:** 🟠 High (financial-system correctness; not remotely exploitable to steal a *different* user's money since Cognito subs aren't guessable, but it made the feature non-functional and removed the only automatic check on payout amounts).
- **Status: FIXED.** Driver self-service routes now resolve the caller's real `User.id` first (`requireOwnUserId`, mirroring the `findOwnDriver` pattern used everywhere else). `calculatePayoutForPeriod` now resolves the `Driver` record before querying `Trip`/`DriverSubscription`. Also fixed 6 `any`-typed returns (now `Payout` / a proper `Prisma.PayoutGetPayload` type) and an unvalidated `status` query param (now a real `z.enum`).
- **Tests added:** new `backend/src/routes/payouts.routes.test.ts` (6 tests) — bank-account round-trip; a driver's history shows an admin-created payout and never shows another driver's; `GET /payouts/:id` 404s cross-driver; `calculatePayoutForPeriod` computes a correct nonzero amount from real completed+paid trips; all Admin-only endpoints reject a Driver; the status filter rejects a non-enum value. All 6 pass.

### H-2 — No content-type/extension allow-list on presigned uploads
- **File:** `backend/src/routes/uploads.routes.ts:13`
- Any authenticated user could presign a PUT for the documents bucket *or* the CloudFront-public assets bucket with an arbitrary `contentType` (`text/html`, `image/svg+xml`, `application/javascript`, ...). Since the assets bucket is served to end users through CloudFront, an uploaded HTML/SVG file could later execute from the app's own asset origin if ever linked to from a user-facing surface.
- **Status: FIXED.** Added a per-bucket content-type allow-list (`documents`: images + PDF; `assets`: images only, explicitly excluding SVG/HTML/anything script-capable everywhere) and a `fileName` regex rejecting path separators/control characters.
- **Tests added:** 3 new tests in `uploads.routes.test.ts` — rejects `text/html`/`image/svg+xml`/`application/javascript`; rejects a PDF for the assets bucket; rejects a path-separator filename. All pass, alongside the 2 pre-existing passing tests.

### H-3 — `fileKey` on driver documents wasn't verified to belong to the caller
- **File:** `backend/src/routes/documents.routes.ts:24`
- `fileKey` was client-supplied free text, never checked against the caller's own presigned-upload prefix. Low practical exploitability (S3 keys here are two nested random UUIDs, impractical to guess), but a missing defense-in-depth check with real integrity implications for what an Admin later trusts as a driver's official document.
- **Status: FIXED.** `POST /documents` now rejects any `fileKey` that doesn't start with `${req.user.sub}/` (the exact prefix `POST /uploads/presign` always issues). **Test added:** rejects a fileKey under a different prefix and confirms nothing was written to the database.

---

## Medium Findings

- **M-1 — Coarse-grained rate limiting.** One flat `300 req / 15 min` bucket covers all of `/api/*`; `/health` and `/api/billing/webhook` fall completely outside even that (registered before the limiter's mount point, or fully handled before the limiter is reached in the middleware chain). *Not blindly changed* per this audit's own instruction to analyze real request patterns rather than tighten arbitrarily — see Remaining Vulnerabilities for the specific, scoped recommendation.
- **M-2 — WebSocket JWT passed as a URL query parameter** (`wss://host/ws?token=...`). A legitimate pattern for browser WS clients (no custom header support), but tokens in URLs risk capture in access/proxy logs if a CDN/ALB is ever placed in front, and there's no re-validation for the life of a long-running socket past the access token's 1-hour expiry.
- **M-3 — No per-connection throttle on WebSocket `location` messages.** A compromised/buggy driver client could flood location updates, each triggering two DB queries.
- **M-4 — Minor info disclosure in error handling.** The Prisma `P2002` branch reflects the violating field name to the client (e.g. "Duplicate value for field: email" — low-risk, common pattern), and `console.error(err)` logs the full raw error object to CloudWatch, which can include user-submitted values for Prisma errors (PII-in-logs risk, not a secrets leak).
- **M-5 — No auth-failure / authorization-failure / webhook-failure CloudWatch alarms.** Only 5xx rate, RDS CPU, and RDS storage alarms exist today. This is self-documented in `monitoring-stack.ts` as an intentional MVP scope, but this audit's own checklist explicitly calls these out as needed before public launch.

## Low Findings

- **L-1** — `express.json()`/`express.raw()` rely on body-parser's implicit 100kb default rather than an explicit limit. Works today; explicit is more self-documenting.
- **L-2** — No `AutoScalingConfiguration` pins a low `MaxSize` on the App Runner service (runs on platform defaults) alongside the AWS Budget alarm that does exist.
- **L-3** — No S3 server access logging configured (reasonable at MVP scale).
- **L-4** — 5 `npm audit` high-severity findings — see Dependency Findings below; all confirmed dev-dependency-only.
- **L-5** — The Google Maps API key ships in the compiled Android APK's manifest, which is expected/necessary for the Maps SDK; its actual safety depends entirely on Google Cloud Console-side restrictions (package name + SHA-1 fingerprint) being configured, which is outside this repo.

---

## Passed Security Checks (verified against actual behavior, not assumed)

| Area | Verification |
|---|---|
| JWT signature/issuer/audience/expiry | `aws-jwt-verify`'s `CognitoJwtVerifier`, never manually decoded or trusted |
| Role/group claims | Always derived server-side from the verified JWT (`req.user.groups`); `requireRole` never trusts a client-asserted role |
| Ownership checks | Correct and consistent across riders, drivers, vehicles, rentals, courier (except the fixed C-2), subscriptions, support tickets, alerts, promotions, loyalty |
| SQL injection | 100% Prisma parameterized queries repo-wide; the one raw query (`$queryRaw\`SELECT 1\``) is a hardcoded literal with no interpolation |
| SSRF | Zero outbound HTTP calls anywhere in the backend (grepped for `fetch`/`axios`/`http.request`) |
| Command injection | Zero `child_process`/`eval`/`new Function` usage anywhere |
| Stripe webhook | Signature verified against raw bytes (`express.raw()` mounted before `express.json()`), tested for missing/invalid signatures, Stripe SDK's own timestamp-tolerance check provides replay protection |
| Payment amounts | Server-derived from the stored `trip.finalFare`, never taken directly from the charge request body (though `finalFare` itself was compromised upstream by C-2, now fixed) |
| S3 buckets | `BLOCK_ALL` public access, SSE encryption, `enforceSSL` (TLS-only), versioned+lifecycle on documents; assets served only via CloudFront + Origin Access Control, bucket itself never public |
| Presigned URLs | Correctly namespaced under the caller's own Cognito `sub`, 5-minute expiry |
| Secrets management | DB credentials and Stripe keys injected into App Runner exclusively via Secrets Manager references (`runtimeEnvironmentSecrets`), never plaintext in the CDK template or image |
| Secrets in repo/history | Zero real secrets found — scanned the full current tree *and* the entire git history (`git log --all -p`) for Stripe/AWS/PEM key patterns |
| GitHub OIDC | Trust policy scoped to `repo:MariaD137/ravelgo:ref:refs/heads/main` (not a wildcard); deploy role permissions scoped to one ECR repo + one App Runner service ARN; 1-hour max session; no static AWS keys anywhere |
| Env validation | Fails closed in production for `ALLOWED_ORIGINS` and Stripe keys (boot-time throw) |
| Security headers | Full Helmet default set present (HSTS, X-Content-Type-Options, X-Frame-Options, CSP, no-referrer) |
| CSRF | Not applicable — zero cookie usage anywhere (Bearer-token auth only) |
| Pagination | Bounded (`pageSize` max 100) everywhere, preventing large-result-set DoS |
| WebSocket authorization | Real JWT verification at connect time; per-trip subscription authorization re-derived from the DB on every `subscribe` message, never trusting client claims; driver location updates re-derive the driver's own identity server-side |
| Flutter secrets | Google Maps key kept out of source via `local.properties` (gitignored), injected only at native build time; zero hardcoded API keys found in any Dart source |

---

## Fixed Vulnerabilities

| ID | Summary | File(s) | Regression test |
|---|---|---|---|
| C-1 | Boot-blocking YAML syntax error | `openapi.yaml` | Full suite: 0/20 → 99/99 passing |
| C-2 | BOLA + fare manipulation on trip status | `trips.routes.ts` | `trips.routes.test.ts` (updated + 1 new) |
| H-1 | Payout driverId confusion (3 different meanings) | `payouts.routes.ts`, `services/payouts.ts` | `payouts.routes.test.ts` (new, 6 tests) |
| H-2 | No upload content-type allow-list | `uploads.routes.ts` | `uploads.routes.test.ts` (3 new) |
| H-3 | No fileKey ownership check | `documents.routes.ts` | `documents.routes.test.ts` (1 new) |
| — | 10 ESLint errors (`no-explicit-any`) in the payout module, 2 elsewhere | `services/payouts.ts`, `payouts.routes.ts`, `lib/errors.ts`, `middleware/error-handler.ts` | `npm run lint` now 0 errors |
| — | `backend-ci.yml` never set `DOCUMENTS_BUCKET`/`ASSETS_BUCKET`, so the uploads presign test would fail in real CI too | `.github/workflows/backend-ci.yml` | Confirmed locally: test passes only once these are set |

## Remaining Vulnerabilities / Recommendations Not Yet Implemented

- **`estimatedFare` at trip creation is still client-supplied**, not computed from the working `GET /pricing/quote` engine. Fixing this requires a product decision (should the client ever be allowed to show its own estimate, or must the shown estimate always equal the server's quote?) that shouldn't be made silently inside a security fix — flagged here explicitly rather than papered over.
- **Rate limiting is still one flat bucket.** Recommended, scoped next step (not implemented, since it needs a deliberate rollout decision, not a reflexive tightening): a stricter limiter on `/api/uploads/presign` and `/api/trips/:id/charge` specifically (both have real cost/abuse consequences — storage and Stripe API calls respectively), and bringing `/health` and `/api/billing/webhook` under some limit instead of none at all.
- **WebSocket token-in-URL and lack of long-lived-socket re-validation** (M-2) — not fixed; would need a client-side change (a post-connect auth message instead of a query param) coordinated with whichever app eventually uses the realtime feed.
- **Missing auth/authz/webhook-failure CloudWatch alarms** (M-5) — not added to `infra/` in this pass, since deploying new monitoring infrastructure against a real AWS account is outside what this sandbox can validate; see Needs AWS Configuration below.

## Needs AWS Configuration

- Add CloudWatch alarms for authentication-failure rate, authorization-failure (403) rate, and Stripe webhook-processing failures before public launch.
- Set an explicit `AutoScalingConfiguration` (e.g., a low `MaxSize`) on the App Runner service as a cost ceiling alongside the existing Budget alarm.
- Verify the Google Maps API key is restricted in Google Cloud Console (Android package name + SHA-1 fingerprint) — it ships in the compiled APK by necessity, and restriction is the only control that matters.
- Flip `deletionProtection: false → true` on the RDS instance once this stops being a throwaway MVP database (already self-flagged in `data-stack.ts`'s own comment).
- Enable Cognito's advanced security features (adaptive/risk-based authentication) if brute-force/credential-stuffing protection beyond Cognito's baseline is desired — this backend has **no login endpoints of its own** (auth happens directly against Cognito from the Flutter clients), so that protection is entirely Cognito's configuration, not this Express app's.
- Confirm the GitHub `production` deploy environment (referenced in `backend-deploy.yml`) actually has protection rules (required reviewers) configured in repo settings — this can't be verified from code.

## Needs Stripe Configuration

- The `StripeSecret` in `api-stack.ts` is still deployed with placeholder values (`sk_live_REPLACE_ME`, `whsec_REPLACE_ME`) by design — real keys must be set post-deploy via `aws secretsmanager put-secret-value`, exactly as `docs/AWS-DEPLOYMENT.md` documents. Confirm this manual step has an owner before any real deploy.

## Needs Manual Verification

- Whether the GitHub `production` environment has required-reviewer protection (see above).
- Whether Google Cloud Console API-key restrictions are configured for the Maps key (see above).
- Whether Cognito's advanced security mode is intended to be enabled (see above) — not set in `auth-stack.ts` today, meaning it defaults off.

## Security Regression Tests Added

- `backend/src/routes/payouts.routes.test.ts` — **new file**, 6 tests (bank-account round trip; cross-driver history/detail isolation; real fare calculation from completed trips; Admin-only gating; status-enum validation).
- `backend/src/routes/trips.routes.test.ts` — 1 test updated (now assigns the calling driver to the trip) + 1 new test (`rejects a Driver who isn't assigned to the trip`, asserting 403 and unchanged trip state).
- `backend/src/routes/documents.routes.test.ts` — 1 new test (`rejects a fileKey that doesn't belong to the calling user`).
- `backend/src/routes/uploads.routes.test.ts` — 3 new tests (rejects executable-capable content types; rejects PDF for the public assets bucket; rejects a path-separator filename).

Total: **11 new/updated tests**, all passing. Full suite: **99/99 passing** (up from 0/20 before the openapi.yaml fix).

## Dependency Findings

- `npm audit`: 5 high-severity findings, **all confirmed transitive devDependencies**:
  - `js-yaml@4.3.0` (CVE re: quadratic CPU consumption) — nested under `eslint@9.39.5` → `@eslint/eslintrc`. The backend's own direct, production `js-yaml@5.2.2` dependency (used in `app.ts` to load `openapi.yaml`) is **unaffected** (the CVE only applies to `4.0.0–4.3.0`).
  - `@prisma/config` / `deepmerge-ts` (stack-exhaustion CVE) — under the `prisma` CLI devDependency, not `@prisma/client` (the actual runtime dependency, which is clean).
  - **Verified excluded from the production image**: the Dockerfile's runtime stage runs `npm ci --omit=dev`, confirmed by reproducing that exact install locally — `prisma generate` still succeeds via `@prisma/client`'s own postinstall, no dev-only package is required at runtime.
  - **Recommendation:** run `npm audit fix` on the tooling versions during a normal dependency-maintenance pass; not urgent, zero production exposure.
- Flutter/Dart dependencies were not re-audited in this pass (out of scope for a backend/infra security audit); the three apps currently make no live network calls to any backend, per the separate gap-audit report already on file for this repository.

## AWS Security Findings

- **IAM:** App Runner's `instanceRole` is scoped to exactly what the running container needs (DB secret read, the two specific S3 buckets, the Stripe secret) — no wildcards found. GitHub Actions' deploy role is scoped to one ECR repo + one App Runner service ARN + the one unavoidable-wildcard `ecr:GetAuthorizationToken` action (which AWS's API does not support scoping by resource).
- **Networking:** RDS lives in `PRIVATE_ISOLATED` subnets with **no NAT gateway and no route to the internet**; reachable only from App Runner's VPC connector security group on port 5432. The database is not exposed to the public internet.
- **S3:** Both buckets have `BlockPublicAccess.BLOCK_ALL`, SSE encryption, and `enforceSSL`. Assets are public only via CloudFront + Origin Access Control — the bucket itself is never publicly reachable.
- **ECR:** `imageScanOnPush: true` and a 20-image lifecycle limit are both configured.
- **GitHub OIDC:** trust policy correctly scoped to the specific repo + branch (`main`), not a wildcard — this is one of the more commonly-misconfigured parts of an OIDC setup, and it's done right here.

## Hacker Attack Scenarios Tested

| Scenario | Result before fix | Result after fix |
|---|---|---|
| Driver completes/cancels another driver's trip, sets an arbitrary fare | ✅ Succeeded (403 expected, got 200) | ❌ Blocked — 403, verified by test |
| Driver registers a document under another user's file prefix | ✅ Succeeded (no check existed) | ❌ Blocked — 403, verified by test |
| Any user presigns an upload for an executable/script-capable content type | ✅ Succeeded | ❌ Blocked — 400, verified by test |
| Driver reads another driver's payout by ID | Already blocked (route always filtered by driverId) — but the filter used the *wrong* driverId, so it degenerated into "driver can't read any payout, including their own" | ✅ Correctly isolated per-driver, verified by test |
| Unauthenticated request to any protected endpoint | ✅ Already blocked (401) | Unchanged — still blocked |
| Forged/invalid Stripe webhook signature | ✅ Already blocked (400) | Unchanged — still blocked, tested |
| SQL injection via any string input field | Not exploitable (Prisma parameterization) | Unchanged |
| SSRF via any user-controlled URL | Not applicable (no outbound HTTP calls exist) | Unchanged |

## Cost-Abuse Risks

- `/health` and `/api/billing/webhook` currently sit outside the one rate limiter that does exist — both are cheap per-request (a `SELECT 1` and a signature-verify respectively) but unlimited volume against either would still generate App Runner scaling and CloudWatch log costs. Documented above as M-1; not blindly rate-limited without a real traffic baseline to size the limit against.
- No explicit App Runner `MaxSize` cap exists today (L-2) — the AWS Budget alarm (already configured, 80%/100% thresholds) is the only cost circuit-breaker in place, and it's a post-hoc alert, not a preventive cap.
- Presigned S3 uploads are rate-limited only by the general 300/15min bucket; a user could still request many presigned URLs and never upload (no cost beyond the API call itself — actual storage cost only accrues once bytes are actually PUT to S3, which needs a valid signed URL and the caller's own bandwidth).

---

## Final Go / No-Go

# 🟡 CONDITIONAL GO

**Safe to deploy to a controlled staging/beta AWS environment now.** The critical boot-blocking defect is fixed and verified (99/99 tests passing, clean lint/typecheck/build), the BOLA + payment-manipulation vulnerability is fixed and verified, and the payout system's structural ID-confusion bug is fixed and verified end-to-end with new tests proving real money-calculation correctness.

**Before public production** (i.e., before any of the three Flutter apps are wired to call this backend for real users and real payments), resolve:
1. Real Stripe keys configured (currently placeholders by design).
2. A deliberate decision + fix for `estimatedFare` being client-supplied instead of pricing-engine-computed.
3. Differentiated rate limiting for `/api/uploads/presign`, `/api/trips/:id/charge`, and bringing `/health`/`/api/billing/webhook` under some limit.
4. Auth-failure / authorization-failure / webhook-failure CloudWatch alarms.
5. Confirmation of the "Needs Manual Verification" items above (GitHub environment protection, Google Maps key restriction, Cognito advanced security).

None of items 2–5 are exploitable vulnerabilities discovered in this audit — they are deployment-readiness gates being surfaced explicitly rather than assumed away, per this audit's own standard of proving rather than asserting security.
