# RavelGo — Security & Production Readiness Baseline Audit

**Phase:** 1 (audit only — no code, database, or infrastructure changes were made to produce this report)
**Date:** 2026-09-13
**Scope:** Rider app (`user_app`), Driver app (`driver_app`), Admin app (`admin_app`), backend (Node/Express/TypeScript/Prisma), PostgreSQL (RDS), AWS infrastructure (CDK), CI/CD (GitHub Actions)
**Method:** Direct code/config inspection with exact file:line citations. Every PASS below is backed by cited evidence, not inferred from a library/service's name. Live-environment items that require AWS/Cognito console access are explicitly marked NEEDS VERIFICATION rather than assumed.

**Security document check:** No dedicated security checklist document was found committed in this repository (searched for SECURITY.md, docs/security*, checklist files — none exist). This audit uses the checklist embedded in the audit request as the baseline. No claim is made that a project-specific document's checks were verified, since no such document exists.

**Payment provider verification:** RavelGo uses **Paystack**, not Stripe. Confirmed by direct inspection — all `stripe` references found repo-wide are in comments describing prior removal; no live Stripe SDK, keys, or routes exist anywhere in the codebase.

**Database verification:** RavelGo uses **PostgreSQL** (AWS RDS, `rds.DatabaseInstanceEngine.postgres` version 16.4, `infra/lib/data-stack.ts:33-34`), not SQLite. Confirmed via Prisma schema, migrations, and CDK.

---

## Executive Summary

Seven independent deep-dive passes were run across authentication, authorization (all 26 backend route files), payments/business logic, file uploads/storage/secrets, AWS infrastructure, all three Flutter clients, and rate-limiting/dependencies. The codebase shows a genuinely disciplined security posture in most areas — ownership checks are near-universal and well-tested, webhook signature verification is correct, S3/network isolation is sound, and IAM/OIDC scoping is tight. However, **six HIGH-severity findings** were confirmed with direct code evidence, two of which meet this audit's own stated NO-GO criteria verbatim (an authentication-control bypass and a payment-manipulation vulnerability). No CRITICAL findings were found.

## Overall Security Grade: **C+**
Strong architectural foundations undermined by a small number of concrete, exploitable gaps in payment idempotency and admin authentication enforcement.

## Deployment Verdict

# 🔴 NO-GO (for public production)
# 🟡 CONDITIONAL GO (for continued staging/controlled beta, once Finding 1 and Finding 3 below are triaged)

**Why NO-GO, precisely:** Two confirmed findings fall directly under this audit's own NO-GO criteria, not a judgment call:
- **"Authentication bypass"** — Finding 2 (MFA enforced only in the Flutter UI, never checked by any backend middleware) means a compromised admin credential (phishing, reuse) grants full admin API access with zero second factor, regardless of whether that admin "enabled" MFA in the app.
- **"Payment manipulation vulnerability"** — Finding 3 (refunds are not capped cumulatively) is a directly exploitable path to refund more money than was ever charged.

Everything else in this report is genuinely strong, and neither finding requires an architecture change — both have small, well-scoped fixes (detailed under each finding and prioritized in the Remediation Phase section). This is not a "start over" verdict; it's a "close these two before public users touch real money and real admin sessions" verdict.

---

## Critical Findings
None found.

## High Findings

| # | Finding | Area | File |
|---|---|---|---|
| 1 | Admin accounts provisioned via the documented Cognito-only onboarding path (`scripts/set-role.sh`) silently receive unrestricted SUPER_ADMIN, invisible to the Admin Users management screen | Backend / Auth | `backend/src/lib/admin-permissions.ts:51-62`, `admin-users.routes.ts:79-100` |
| 2 | MFA is enforced only as Flutter UI navigation; no backend middleware ever checks it | Backend / Auth / Admin App | `backend/src/middleware/auth.ts`, `admin_app/lib/views/splash/splash_screen.dart:58-70` |
| 3 | Refund amount is checked per-call, not cumulatively — repeated/concurrent partial or full refunds can exceed the original payment | Backend / Payments | `backend/src/routes/payments.routes.ts:193-216, 240-248` |
| 4 | Wallet top-up webhook credit has a TOCTOU race — the only webhook branch that doesn't use this codebase's own atomic conditional-update pattern, allowing a duplicate/redelivered webhook to double-credit a wallet | Backend / Payments | `backend/src/services/wallet.ts:9-19` |
| 5 | `trust proxy` is never configured in Express; all rate limiters key on `req.ip`, which behind App Runner's managed edge is not the real client IP — limiter behavior is unreliable in both directions (can over-block all users sharing an internal hop, or fail to isolate a genuine abuser) | Backend / Rate limiting | `backend/src/app.ts` (absent), `middleware/rate-limit.ts:26-45` |
| 6 | `npm audit` (backend, production deps) reports 3 high-severity advisories in the `prisma → @prisma/config → deepmerge-ts` chain with no override in place | Backend / Dependencies | `backend/package.json:32,39-46` |

## Medium Findings

| # | Finding | Area | File |
|---|---|---|---|
| 7 | Sign-out never revokes the refresh token server-side in any of the three apps (`signOut()` called without `revokeRefreshToken: true`, `globalSignOut()` never used) — a stolen token remains valid up to 30 days after the user believes they've logged out | All 3 apps / Auth | `admin_app/lib/services/auth_service.dart:332`, `user_app/…:210`, `driver_app/…:216` |
| 8 | Cognito access/ID/refresh tokens stored in `SharedPreferences`/`localStorage` (not Keychain/Keystore via `flutter_secure_storage`) in all three apps — most severe for `admin_app` since the same session carries Admin-group privileges | All 3 apps / Client storage | `admin_app/…/auth_service.dart:15-39`, `user_app/…`, `driver_app/…` |
| 9 | Driver dual-active-job conflict (holding a ride and a delivery simultaneously) is enforced by an app-level pre-check only, with no DB-level constraint analogous to the rental-booking exclusion constraint the codebase already uses elsewhere | Backend / Business logic | `backend/src/lib/driver-conflicts.ts:18-28`, `services/matching.ts:103-114` |
| 10 | RDS TLS-in-transit enforcement relies on an unverified AWS default (`rds.force_ssl`) rather than an explicit CDK-pinned parameter group | AWS / Database | `infra/lib/data-stack.ts:32-51` |
| 11 | WAF's per-IP rate limit (2000 req/5min) doesn't prevent a modestly distributed (not sophisticated) attacker from exhausting the single App Runner instance (`MaxSize=1`, a deliberate documented trade-off for the in-memory realtime hub) | AWS / Availability | `infra/lib/api-stack.ts:96-113, 331-344` |
| 12 | `brace-expansion` DoS advisory present via 3 dev-only dependency paths (eslint, ts-node-dev); an existing `overrides` entry covers only a 4th, unrelated path | Backend / Dependencies (dev-only) | `backend/package.json:41-44` |

## Low Findings

| # | Finding | Area | File |
|---|---|---|---|
| 13 | WebSocket auth accepts a `?token=` query-string fallback (URL-loggable) alongside the preferred header-based method | Backend / Realtime | `backend/src/realtime/server.ts:70-78` |
| 14 | `GET /rentals/:id` and `GET /stays/:id` don't filter non-`APPROVED` listings for non-owner/non-admin callers, unlike their list-endpoint counterparts | Backend / Authorization | `backend/src/routes/rentals.routes.ts`, `stays.routes.ts` |
| 15 | Promotion `maxRedemptions` cap is checked via a plain read before a later write, not an atomic conditional update — bounded over-redemption possible under concurrency (per-user cap still holds via a separate unique constraint) | Backend / Business logic | `backend/src/routes/loyalty.routes.ts:80-92` |
| 16 | Backend Docker image runs as root (no `USER` directive) | Backend / Docker | `backend/Dockerfile:22-42` |
| 17 | No magic-byte/file-signature validation on uploads (client-declared `contentType` trusted) — mitigated by private buckets, no server-side execution of uploaded content, and SVG/HTML already excluded from the allowlist | Backend / File uploads | `backend/src/routes/uploads.routes.ts:44,62-66,85-90` |
| 18 | CloudFront TLS minimum-protocol-version not explicitly pinned in CDK (currently relies on the default `*.cloudfront.net` cert's AWS-enforced TLS 1.2) | AWS / Storage | `infra/lib/storage-stack.ts:80-87` |
| 19 | CI deploy role can write to the public web-assets bucket and invalidate the CDN — proportionate to its job, but real attack surface if the GitHub OIDC trust or workflow is ever compromised | AWS / CI/CD | `infra/lib/ci-stack.ts:163-164,178-191` |

## Needs Verification (cannot be confirmed from the repository alone)

- Live Cognito User Pool console settings (MFA enforcement, `AdvancedSecurityMode`, token validity) actually match `infra/lib/auth-stack.ts` — CDK is only authoritative if it was the last thing deployed.
- Whether any existing production `User` rows have `adminRole = null` (the population directly affected by Finding 1).
- Live RDS parameter group value for `rds.force_ssl`.
- Google Maps API key's actual restriction settings (Android package/SHA-1, iOS bundle ID, API scoping) — only checkable in Google Cloud Console.
- Cognito's built-in brute-force/lockout thresholds for sign-in (AWS-managed, not configured in this repo).
- `amazon_cognito_identity_dart_2` (v3.8.2, one major behind v4.0.1) — no specific CVE confirmed against 3.8.2 from this environment; recommend checking the 4.x changelog before the next dependency bump.
- Live WAF/CloudWatch alarm attachment state in the actual deployed stacks, if it has drifted from source.

---

## Rider App Findings
No rider-specific HIGH/MEDIUM findings beyond the cross-cutting client-storage item (Finding 8) and the sign-out item (Finding 7), both shared across all three apps. Payment flow (Paystack checkout via `url_launcher` in-app-browser, never a bespoke WebView) is a sound pattern — see Payment Findings.

## Driver App Findings
Same cross-cutting items as Rider (Findings 7, 8). Document/vehicle-photo upload ownership binding is correctly enforced server-side (see File Upload Findings and Authorization Findings — `vehicles.routes.ts`, `documents.routes.ts` both PASS with cited evidence).

## Admin App Findings
Highest-risk app, and where the two HIGH auth findings concentrate:
- Finding 1 (silent SUPER_ADMIN provisioning) and Finding 2 (MFA is UI-only) both center on `admin_app`'s authentication path.
- Client-side role check (`AuthService.isAdmin`) is correctly documented and confirmed as UX-only — the backend independently re-enforces `requireRole("Admin")`/`requireAdminPermission` on every route (PASS).
- No app-lock (PIN/biometric re-entry) exists — not treated as a standalone finding per the audit's own guidance, but worth prioritizing for `admin_app` specifically given elevated privileges and Finding 8's token-storage gap compounding the risk of an unattended unlocked device.

## Backend Findings
See Authentication, Authorization, Payment, and Rate Limiting sections below — this is where the majority of both PASS evidence and all HIGH findings live.

## Database Findings
- PostgreSQL 16.4, RDS, `PRIVATE_ISOLATED` subnets, `storageEncrypted: true`, 7-day backup retention, deletion protection in production — all confirmed PASS (`infra/lib/data-stack.ts`).
- Row-Level Security exists on financial tables per an earlier PR in this repo's history (`DriverBankAccount`, `Payment`, `Payout`) — not re-verified line-by-line in this pass, flagged for a follow-up spot-check if not already covered by that PR's own tests.
- TLS-in-transit: Medium finding #10 above (relies on AWS default, not explicitly pinned).
- No SQLite usage anywhere — confirmed.

## Payment Findings
Paystack-only (Stripe fully removed). Webhook signature verification (HMAC-SHA512, raw body preserved before global JSON parsing, verify-before-fulfill against Paystack's own API) is correctly implemented — PASS. Price/fare/rental-total authority is server-computed everywhere checked, with a regression test explicitly proving a client-injected `driverEarnings`/`platformCommission` has no effect. Payout duplication is DB-enforced (`@@unique([driverId, period])`). The two HIGH findings (refund cap, wallet webhook race) are the exceptions to an otherwise strong pattern — see Findings 3 and 4 above for full detail.

## AWS Findings
Network isolation, IAM least-privilege (including the GitHub OIDC trust policy — exact-match subject conditions, no wildcard, confirmed unable to be assumed by a fork/different branch/different repo), Secrets Manager usage, and WAF association are all PASS with cited evidence. Two Medium findings (RDS TLS enforcement, single-instance DoS surface) and two Low findings (CloudFront TLS pinning, CI bucket-write scope) round out the AWS section — none are CRITICAL/HIGH.

## CI/CD Findings
GitHub OIDC scoping is correctly restricted to this exact repo+branch/environment. No hardcoded secrets found in any workflow file — all reference `${{ secrets.* }}` or repository variables. CI-dummy values used in test workflows are clearly named as such, not real credentials.

## Dependency Findings
Backend production dependencies: 3 high-severity advisories in the `prisma`/`deepmerge-ts` chain (Finding 6), no override yet. Backend dev dependencies: `brace-expansion` DoS in 3 of 4 paths, one already overridden (Finding 12, dev-only). `infra/`: **zero vulnerabilities** at any severity. All three Flutter apps have committed `pubspec.lock` files (pinned); `amazon_cognito_identity_dart_2` is one major version behind across all three apps (NEEDS VERIFICATION — no confirmed CVE).

## File Upload Findings
Ownership binding at upload time (S3 key always prefixed with the caller's verified Cognito `sub`), server-enforced size ceiling (via S3 `ContentLength`, not just a client check), filename sanitization, SVG/HTML excluded from all allowlists, short (5-minute) presigned URL expiries, and document-read ownership checks are all PASS with cited evidence. Two Low findings: no magic-byte validation (accepted risk given private buckets + no server-side execution of uploaded content) and the backend Docker image running as root.

## Authentication Findings
JWT validation uses `aws-jwt-verify` correctly (signature, issuer, `token_use` pinned to `access`, audience, expiration — all verified, confirmed no hand-rolled parsing). `requireAuth`/`requireRole` derive identity exclusively from the verified token, never client input. Both HIGH auth findings (1, 2) and both Medium auth findings (7, 8) are detailed above.

## Authorization Findings
The strongest section of this audit: all 26 backend route files were checked; 24 are a clean PASS with consistent ownership-check patterns and strong test coverage (explicit 403/404 tests for cross-user/cross-driver access across trips, courier requests, documents, vehicles, payouts, admin-users). Only two Low findings (rentals/stays detail-route status filtering) — no genuine IDOR into private or financial data was found anywhere.

## Rate Limiting Findings
High-value endpoints (payments, refunds, payouts, uploads, admin invites) are consistently gated behind `sensitiveLimiter`; the webhook endpoint has its own limiter plus signature verification; a sane global default (300/15min) covers everything else. The one HIGH finding (#5, `trust proxy` unset) undermines the reliability of every one of these limiters behind App Runner and should be treated as the practical priority within this section, even though rate limiting is "present" everywhere it should be.

## Monitoring Findings
CloudWatch alarms exist for App Runner 5xx rate, RDS CPU/storage, and four security-event metric filters (auth failures, authz failures, rate-limit hits, payment failures) — all wired to a real SNS topic with an email subscription, plus a cost/budget alarm. Explicitly absent (documented as deferred-by-design pending real production traffic, not oversights): API latency alarms, DB connection-pool exhaustion alarms, a standing alarm on App Runner deployment failures (currently only caught synchronously by the CI pipeline itself), and admin-activity anomaly detection.

## Cost-Abuse Findings
WAF rate limiting and the single-instance App Runner configuration are cost-conscious by explicit design (documented trade-off for the realtime hub's in-memory state). The residual gap is Medium finding #11 — availability risk under modest distributed load, not runaway AWS cost per se, since App Runner is pinned to `MaxSize: 1` (cost bounded, availability is the trade-off).

---

## Security Tests Performed
- Full read of `backend/src/middleware/auth.ts`, `admin-permissions.ts`, and their test files.
- Line-by-line review of all 26 files in `backend/src/routes/*.routes.ts` against their matching `*.routes.test.ts` files for ownership/role enforcement.
- Full trace of the Paystack webhook path (signature verification, raw-body handling, idempotency pattern) and every payment-bearing service (`wallet.ts`, `trip-payment.ts`, `courier-payment.ts`, `rental-payment.ts`, `payouts.ts`, `ledger.ts`).
- Full read of `backend/src/routes/uploads.routes.ts`, `documents.routes.ts`, `vehicles.routes.ts` (photo-key ownership) and `infra/lib/storage-stack.ts`.
- Full read of every `infra/lib/*.ts` CDK stack and `infra/bin/infra.ts`.
- Full read of all three apps' `auth_service.dart`, `api_client.dart`, and a repo-wide grep for WebViews, deep links, TLS-bypass anti-patterns, and biometric/app-lock usage.
- `npm audit --omit=dev` and full `npm audit` run (read-only) in both `backend/` and `infra/`.
- `flutter pub outdated` run (read-only) in all three Flutter app directories.
- Repo-wide secrets scan (AWS keys, private key blocks, live-looking API keys, SMTP credentials) across all tracked files; `git ls-files`/`git check-ignore` used to confirm no real `.env` file is tracked.

## Tests Not Possible From Repository Alone
- Live Cognito console configuration (MFA enforcement state, `AdvancedSecurityMode`, actual token validity in the deployed pool).
- Live RDS parameter group values (`rds.force_ssl`).
- Google Maps API key restriction settings (Google Cloud Console only).
- Actual production `User` table contents (which admin rows, if any, currently have `adminRole = null`).
- Live penetration testing against a running staging/production instance (this session had no working AWS credentials or reachable staging endpoint at time of audit — see prior session notes on the ongoing staging deployment issue).
- CVE-level confirmation for `amazon_cognito_identity_dart_2` 3.8.2 against pub.dev's advisory database (no outbound advisory lookup performed).
