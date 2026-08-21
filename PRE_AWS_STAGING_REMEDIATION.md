# RavelGo — Pre-AWS Staging Remediation Report

**Scope:** the 10 P0/P1 findings from the Backend/API Completeness Audit.
**Not in scope, not touched:** AWS infrastructure, Stripe Connect, Flutter apps, anything on the P2 deferral list.

Every fix below is verified against a live Postgres 16 database, a compiled production build, and the real test suite — not just read from the diff.

---

## Final verification results

| Check | Result |
|---|---|
| `npm install` (`npm ci`) | Clean |
| `npm run build` (`tsc -p tsconfig.json`) | Clean |
| `npx tsc --noEmit` | Clean, zero errors |
| `npm test` | **130/130 passing**, 0 failing (run twice: once with ambient credentials, once with `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` explicitly unset to reproduce real CI — both green) |
| Compiled server boot (`NODE_ENV=production node dist/index.js`) | Boots, `GET /health` → 200, `GET /openapi.json` → 200 |
| `openapi.yaml` parses (`js-yaml`) | Valid, 63 paths, cross-checked 1:1 against every registered Express route |
| `npx prisma migrate deploy` / `migrate status` | 4 migrations apply cleanly, in order |
| `npx prisma migrate diff` (schema vs. migration history) | No difference detected — zero drift |
| `npm audit` | 5 pre-existing high-severity advisories, all in devDependency tooling (`eslint`'s bundled `js-yaml`/`brace-expansion`, `prisma` CLI's `@prisma/config`→`deepmerge-ts`) — **unchanged by this remediation**, none reach the runtime dependency graph shipped in the Docker image |
| `npm run lint` | **10 errors / 2 warnings, unchanged from before this remediation** (see "Intentionally deferred" below) — this remediation introduced **zero new lint issues**, confirmed by running lint against the original commit and diffing |
| `git diff` review | 13 files modified, 4 new files, all directly traceable to one of the 10 findings — no unrelated files touched (no Flutter apps, no `infra/`, no Stripe Connect, no untouched route files like `admin.routes.ts`, `drivers.routes.ts`, `vehicles.routes.ts`, etc.) |
| Existing tests | **Zero deleted, zero weakened.** One test (`trips.routes.test.ts`) was corrected — see Finding 3 below, its assertions are unchanged, only its setup was fixed to no longer exercise the IDOR bug it had accidentally been validating as "working." |

---

## P0 Findings

### 1. OpenAPI YAML boot failure

- **Finding:** `backend/openapi.yaml` lines 1615/1617 had unquoted `description` values containing commas inside YAML flow mappings (`description: Field name or path (e.g., "email", "address.zipCode")`), which is invalid YAML. `src/app.ts` parses this file synchronously at module load, so the process threw an uncaught `YAMLException` and exited immediately — the compiled server could not start, and all 20 test files failed to even import `app.ts`.
- **Root cause:** unescaped commas inside an unquoted flow-mapping scalar.
- **Existing code reused:** none needed — pure syntax fix.
- **Minimal fix:** wrapped both description values in double quotes with the inner double quotes escaped (`"Field name or path (e.g., \"email\", \"address.zipCode\")"`). No other OpenAPI content touched.
- **Files changed:** `backend/openapi.yaml`.
- **Tests added:** none needed — existing `openapi.routes.test.ts` (`GET /openapi.json`, `GET /docs`) now exercises this on every run, since it can only run at all once the file parses.
- **Verification:** `js-yaml` parses the file; compiled server boots (`node dist/index.js` → "RavelGo backend listening..."); `GET /health` and `GET /openapi.json` both return 200 against the running production build.
- **Security impact:** none (availability bug, not a security bug) — but this was the single highest-severity finding: the application could not run at all.

### 2. Driver payout Cognito-sub/User.id bug

- **Finding:** `src/routes/payouts.routes.ts` used `req.user!.sub` (the Cognito sub) directly as `driverId` for all four driver-facing endpoints (`POST/GET /payouts/bank-account`, `GET /payouts/history`, `GET /payouts/:id`), but `Payout.driverId` and `DriverBankAccount.driverId` are foreign keys to `User.id` — a different, internally-generated UUID. Every call either threw a foreign-key-constraint violation (writes) or matched nothing (reads).
- **Root cause:** missing the `cognitoSub → User.id` resolution step that every other self-service route in the codebase already does.
- **Existing code reused:** the exact pattern already used by `findOwnDriver()` in `vehicles.routes.ts`, `courier.routes.ts`, `subscriptions.routes.ts`, `rentals.routes.ts`, and `/riders/me` in `riders.routes.ts` — look up the caller's own `User` row by `cognitoSub` first.
- **Minimal fix:** added `findOwnDriverUser(cognitoSub)` (resolves `User` by `cognitoSub`, confirms `role === "DRIVER"`) and used `user.id` as `driverId` in all four driver-facing handlers. **Admin-facing routes (`/payouts/calculate`, `/payouts/create`, `/payouts/:id/process`, `/payouts/:id/complete`, `/payouts/:id/fail`, `GET /payouts`) were already correct and were not touched.**
- **Files changed:** `backend/src/routes/payouts.routes.ts`.
- **Tests added:** `backend/src/routes/payouts.routes.test.ts` (new file, 9 tests) — driver can create/update their own bank account, can read it back, can list their own payout history, can read one of their own payouts, gets 404 (not another driver's data) for a payout that belongs to someone else, a valid token with no matching `User` row is rejected safely, a `User` row with the wrong role is rejected, unauthenticated and wrong-role (Rider) callers are rejected.
- **Verification:** all 9 pass against a live Postgres instance with real foreign-key constraints (not mocked).
- **Security impact:** fixes a completely non-functional feature (driver payout self-service), not a new access-control gap — the bug caused hard failures, not silent unauthorized access.

### 3. Trip status authorization / IDOR

- **Finding:** `PATCH /trips/:id/status` required role `Driver` or `Admin` but never checked that the calling driver was the trip's *assigned* driver. Any authenticated Driver account could complete, cancel, or dispute **any trip in the system** and set an arbitrary `finalFare`. The repo's own test proved this: it authenticated as a Cognito sub with no `Driver` record at all and successfully completed a stranger's trip.
- **Root cause:** missing ownership check before applying the status change.
- **Existing code reused:** the identical ownership-check shape already used (correctly) by `PATCH /courier-requests/:id/status` in the same codebase — resolve the caller's own `Driver` via `cognitoSub`, compare to `trip.driverId`, allow `Admin` to bypass.
- **Minimal fix:** fetch the trip first; if the caller isn't in the `Admin` group, resolve their `Driver` record and require `driver.id === trip.driverId`, else `403`. Nonexistent trip → `404`. Admin behavior is completely unchanged (still bypasses the ownership check, as courier's admin path does).
- **Files changed:** `backend/src/routes/trips.routes.ts`.
- **Existing test corrected, not deleted or weakened:** `"PATCH /api/trips/:id/status lets a Driver or Admin advance trip status"` previously authenticated as an *unrelated* driver with no `Driver` row and asserted `200` — that assertion was validating the bug itself. It was renamed to `"...lets the trip's assigned Driver advance its status"` and its setup fixed to create and assign a real `Driver` to the trip; its original assertions (`200`, `status: COMPLETED`, `completedAt` set) are unchanged.
- **Tests added:** assigned driver can update (fixed above), Admin can update any trip, an unassigned Driver is rejected `403` and the trip is left untouched, a Driver-group caller with **no** `Driver` record at all is rejected `403` (the exact scenario the old test exploited), a Rider is rejected `403`, a nonexistent trip returns `404`.
- **Verification:** all pass; the previously-exploitable scenario is now explicitly asserted to fail.
- **Security impact:** closes a real IDOR that allowed cross-account trip tampering and fare manipulation feeding directly into `POST /trips/:id/charge`.

### 4. Rider trip cancellation

- **Finding:** riders had no way to cancel a trip they requested — only `Driver`/`Admin` could call `PATCH /trips/:id/status`, and `CANCELLED` wasn't reachable from any rider-facing endpoint.
- **Inspection of existing lifecycle:** `TripStatus` already has `CANCELLED`; the trip lifecycle is `REQUESTED → MATCHED → IN_PROGRESS → COMPLETED`, with `CANCELLED`/`DISPUTED` as terminal off-ramps. No new states were introduced.
- **Minimal fix:** added `PATCH /trips/:id/cancel`, Rider-only. Resolves `cognitoSub → User.id`, requires `trip.riderId === user.id` (403 otherwise), only allowed while `trip.status` is `REQUESTED` or `MATCHED` (409 otherwise — once a driver has started the trip there's nothing left to call off), sets `status: CANCELLED`. Admin cancellation is untouched — it already goes through the existing `PATCH /trips/:id/status` with `status=CANCELLED`.
- **Files changed:** `backend/src/routes/trips.routes.ts`, `backend/openapi.yaml` (documented the new endpoint).
- **Tests added:** owning rider cancels a `REQUESTED` trip, owning rider cancels a `MATCHED` trip, a different rider is rejected `403` (trip left untouched), the assigned Driver is rejected `403` (rider-only endpoint), cancelling an `IN_PROGRESS` trip is rejected `409`, cancelling an already-`COMPLETED` trip is rejected `409`, nonexistent trip → `404`.
- **Verification:** all pass.
- **Security impact:** none negative — closes a functional gap without weakening any existing check.

---

## P1 Findings

### 5. Server-authoritative fare

- **Finding:** `estimatedFare` on trip creation was entirely client-supplied with no validation; `finalFare` on trip completion was entirely driver-supplied, bounded only by `> 0`. The existing pricing engine (`PricingRule`/`SurgeZone`/`GET /pricing/quote`) was never actually consulted.
- **Existing code reused:** no new pricing engine was built. The exact formula and lookup logic from `GET /pricing/quote` was extracted, unchanged, into `src/services/pricing.ts` (`getActivePricingRule`, `getSurgeMultiplier`, `computeFare`) and `pricing.routes.ts` was refactored to call the shared functions instead of duplicating the logic — confirmed behavior-identical by running its existing test suite unchanged (7/7 still pass).
- **Minimal fix, exact rule implemented:**
  - **At creation (`POST /trips`):** `distanceKm`/`durationMinutes`/`zone` are now accepted as optional inputs (the same inputs `GET /pricing/quote` already takes). If both `distanceKm` and `durationMinutes` are given, `estimatedFare` is computed server-side from the active `PricingRule`/`SurgeZone` and any client-supplied `estimatedFare` is **ignored**. If they're omitted (back-compat), `estimatedFare` is still required from the client, but is rejected with `400` if it's below the active `PricingRule`'s flat base fare. With **no** active `PricingRule` configured at all, the client's value is accepted as-is (preserves current dev/test behavior where no rule is seeded).
  - **At completion (`PATCH /trips/:id/status`, `status=COMPLETED`):** a given `finalFare` must fall within **0.5x–2x** the trip's own `estimatedFare` (`FINAL_FARE_MIN_RATIO`/`FINAL_FARE_MAX_RATIO` in `src/services/pricing.ts`), else `400`. There's no persisted actual-distance-traveled to recompute an exact figure from (driver location is in-memory/live-only, per `docs/realtime-architecture.md`), so bounding against the trip's own server-established estimate is the smallest check that rules out an arbitrary/unrelated number reaching `POST /trips/:id/charge`, while still allowing legitimate variance (traffic, waiting time, route changes).
- **Files changed:** `backend/src/services/pricing.ts` (new), `backend/src/routes/pricing.routes.ts` (refactor only, behavior-identical), `backend/src/routes/trips.routes.ts`, `backend/openapi.yaml`.
- **Tests added:** `estimatedFare` computed server-side from distance/duration, ignoring a fabricated client value (`999999` → correctly computed `16`); surge multiplier applied server-side; a client `estimatedFare` materially below the active rule's base fare is rejected `400`; a plain client `estimatedFare` is still accepted when no rule is active (back-compat); missing `estimatedFare` with no distance data is rejected `400`; a `finalFare` far above the 2x band is rejected `400` (trip left untouched); far below the 0.5x band is rejected `400`; a `finalFare` within the band is accepted.
- **Verification:** all pass; `pricing.routes.test.ts` (7 tests, unchanged) still passes after the extraction, confirming the refactor didn't change `GET /pricing/quote`'s behavior.
- **Security impact:** closes the fare-manipulation vector this audit identified as compounding Finding 3 — a client (or, after Finding 3's fix, only the assigned driver) can no longer set an unrelated fare.

### 6. Rate limiting behind AWS App Runner

- **Finding:** `express-rate-limit` was configured, but Express's `trust proxy` was never set. Behind App Runner's front-end proxy, every request's `req.ip` would resolve to the proxy's own address, collapsing the 300-req/15-min budget into one shared pool for all traffic instead of per caller.
- **Minimal fix:** `app.set("trust proxy", 1)` — trusts exactly one hop (App Runner's single proxy layer), not `true` (which would trust an arbitrary `X-Forwarded-For` chain and let a client spoof its own address). Harmless locally: with no header present, `req.ip` still falls back to the direct socket address exactly as before.
- **Files changed:** `backend/src/app.ts`.
- **Tests added:** `backend/src/middleware/rate-limit.test.ts` (new, 3 tests) — asserts `app.get("trust proxy") === 1`; with trust-proxy configured, two different `X-Forwarded-For` clients each get their own rate-limit budget (one gets `429` after exhausting its own limit, the other is unaffected); **and, to concretely demonstrate the bug being fixed:** without trust-proxy configured, distinct `X-Forwarded-For` clients collapse into one shared budget (reproduces the exact vulnerability).
- **Verification:** all 3 pass.
- **Security impact:** restores per-client rate limiting; without this, the app would effectively self-DoS all users after ~300 total requests/15min platform-wide once deployed.

### 7. CI S3 environment configuration

- **Finding:** `DOCUMENTS_BUCKET`/`ASSETS_BUCKET` weren't set in `backend-ci.yml`, so `uploads.routes.test.ts`'s presign test failed with `500` ("bucket not configured"). Investigating further: setting **only** the bucket names is not sufficient — with no AWS credentials configured (as intended: none belong in CI), the AWS SDK's credential-provider chain hangs trying IMDS/ECS endpoints that don't exist on a GitHub Actions runner, rather than failing fast. Reproduced directly: the test suite hung past a 30-second timeout with bucket names set but no credentials.
- **Minimal fix, two parts, no AWS credentials added anywhere:**
  1. Added dummy `DOCUMENTS_BUCKET`/`ASSETS_BUCKET` values to `backend-ci.yml` (not real bucket names).
  2. Added `mockPresignedUrl()` to `src/test/helpers.ts`, mocking `@aws-sdk/s3-request-presigner`'s `getSignedUrl` — the same pattern already used for Stripe (`mockPaymentIntentCreate`). (Note: this required importing the presigner module via `import x = require(...)` rather than `import * as x` — TypeScript's namespace-import helper copies this particular package's exports onto a non-configurable object that `mock.method()` can't redefine; documented inline.)
- **Files changed:** `.github/workflows/backend-ci.yml`, `backend/src/test/helpers.ts`, `backend/src/routes/uploads.routes.test.ts` (one line: calls the new mock).
- **Tests added:** none new — the existing 3 `uploads.routes.test.ts` tests now pass deterministically.
- **Verification:** ran the full suite with `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` explicitly unset (reproducing real CI, which has none) — all 130 tests pass in under 2 minutes, no hang.
- **Security impact:** none — pure CI reliability fix; confirms no AWS credentials are needed to run this suite anywhere.

### 8. Payout OpenAPI documentation

- **Finding:** the entire `/payouts/*` route family (9 real endpoints) was missing from `openapi.yaml`.
- **Minimal fix:** documented all 9 actual endpoints — `bank-account` (GET/POST), `history`, `{id}` (get one), `calculate`, `create`, `{id}/process`, `{id}/complete`, `{id}/fail`, and the admin list (`GET /payouts`) — read directly from `payouts.routes.ts`'s actual request/response/auth/validation/error behavior (no invented endpoints, no invented fields). Added `DriverBankAccountInput`, `DriverBankAccount`, `Payout`, `PayoutCalculation`, `PaginatedPayout` schemas and a `Payouts` tag, matching the existing schema style.
- **Files changed:** `backend/openapi.yaml`.
- **Verification:** the spec parses; a script cross-checking every registered Express route path against every documented OpenAPI path confirms **exact 1:1 match, zero gaps in either direction** across all 63 paths; `openapi.routes.test.ts` still passes.
- **Security impact:** none — documentation only.

### 9. Enforce suspended user status

- **Finding:** `User.suspended` was settable by an Admin but never checked anywhere in the request pipeline — a suspended Rider retained full API access.
- **Root cause:** `requireAuth` verified the JWT but never consulted the database.
- **Minimal fix:** `requireAuth` now looks up the caller's `User` row after verifying the token and rejects with `403` if `suspended: true` — **except for the `Admin` group**, which is exempt so a suspended Admin account can still perform recovery actions (e.g., un-suspending other users). A caller with no `User` row yet (first call right after Cognito sign-up, before `POST /riders/me`/`POST /drivers/me` has run) is not blocked — suspension only applies once a profile exists.
- **Files changed:** `backend/src/middleware/auth.ts`.
- **Tests added:** `backend/src/middleware/suspension.test.ts` (new, 8 tests) — active Rider unaffected; suspended Rider rejected `403` on a profile read *and* on trip creation; active Driver unaffected; a suspended Driver (`User.suspended`, distinct from `Driver.status`) is rejected; an Admin whose own `User` row is suspended still retains access (no admin lockout); an Admin can still un-suspend another user (recovery path stays open); a valid token with no `User` row yet is not blocked.
- **Verification:** all 8 pass.
- **Security impact:** closes the gap — admin suspension now actually removes API access for the suspended account, with an explicit, tested exemption preventing admin self-lockout.

### 10. Driver/courier matching race condition

- **Finding:** `matchDriverToTrip` (trip matching) and `PATCH /courier-requests/:id/accept` both did a read-then-write with no atomicity — two concurrent requests could read the same available driver before either wrote, double-booking them.
- **Existing capability used:** Prisma's `$transaction` (interactive transactions with `isolationLevel`) for the cross-row case, and Prisma's `updateMany` with a conditional `WHERE` for the single-row case — no schema change, no new architecture.
- **Minimal fix:**
  - **`matchDriverToTrip`:** the read (which driver is free — a condition that spans *other* Trip rows, so it can't be expressed as a single-row conditional update) and the write (assign them) now run inside one `SERIALIZABLE` Prisma transaction. Postgres aborts the losing concurrent transaction with a serialization failure (Prisma error `P2034`), which is caught and treated the same as "no driver was available this attempt" — the trip is left `REQUESTED`, exactly like the existing no-driver-available case, rather than surfacing a `500`.
  - **`PATCH /courier-requests/:id/accept`:** replaced the separate read-check-then-update with a single atomic `updateMany({ where: { id, status: "REQUESTED", driverId: null }, data: {...} })` and checked its `count`. Only the update that actually matches the still-open condition changes any rows; a losing concurrent request matches zero rows and falls through to the existing `409`.
- **Files changed:** `backend/src/services/matching.ts`, `backend/src/routes/courier.routes.ts`.
- **Tests added:** two riders firing concurrent `POST /trips` requests against exactly one available driver — asserts one trip is `MATCHED` and the other stays `REQUESTED`, and the driver has exactly one trip assigned to them (not two); two drivers firing concurrent `PATCH /courier-requests/:id/accept` against the same request — asserts exactly one gets `200`/`MATCHED` and the other gets `409`, and the request ends up with exactly one driver assigned.
- **Verification:** both concurrency tests pass (run with real concurrent HTTP requests via `Promise.all` against the live app, not simulated).
- **Security impact:** none directly — this is a correctness/data-integrity fix preventing driver double-booking under concurrent load.

---

## Intentionally deferred (not touched in this pass)

- **Stripe Connect** (`services/payouts.ts`'s `processPayout` still simulates success) — explicitly out of scope per instructions; not faked, not claimed complete.
- **Pre-existing lint debt** (10 `@typescript-eslint/no-explicit-any` errors + 2 unused-var warnings in `lib/errors.ts`, `middleware/error-handler.ts`, and `services/payouts.ts`, plus one pre-existing unused-import warning in `app.ts`): confirmed via `git stash` that these existed identically on the base commit, **before this remediation touched anything**. None are in the P0/P1 list, none of my changes require touching those files, and fixing them would mean rewriting working code outside this remediation's scope. This remediation introduced **zero new lint issues** (confirmed by diffing lint output before/after). **This is the one respect in which "CI GREEN" is not fully achieved end-to-end**: `backend-ci.yml`'s `lint` step runs before `test` and would still fail on these pre-existing errors. Build, typecheck, tests, migrations, and OpenAPI validation are all green.
- **Database indexing, admin audit logging, full dispute workflow, automated KYC, RBAC, admin dashboard, PDF export, badge customization, migration folder renaming** — all explicitly P2, untouched.

---

## Final table

| Finding | Status | Tests | AWS Required? |
|---|---|---|---|
| OpenAPI YAML boot crash | FIXED | PASS (compiled server boots; `/health`, `/openapi.json` verified live) | No |
| Driver payout Cognito-sub/User.id bug | FIXED | PASS (9/9 new) | No |
| Trip status IDOR | FIXED | PASS (6/6 new + 1 corrected) | No |
| Rider trip cancellation | FIXED (added) | PASS (7/7 new) | No |
| Fare server-authoritative | FIXED | PASS (7/7 new + 7/7 existing pricing tests unchanged) | No |
| Rate limiting behind App Runner | FIXED | PASS (3/3 new) | No |
| CI S3 env config | FIXED | PASS (verified with no AWS credentials present) | No |
| Payout OpenAPI documentation | FIXED | PASS (spec parses; 63/63 routes cross-checked) | No |
| Suspended rider enforcement | FIXED | PASS (8/8 new) | No |
| Driver/courier matching race | FIXED | PASS (2/2 new concurrency tests) | No |

**Full suite: 130/130 passing, 0 failing, 0 skipped — verified with no AWS credentials present (matching real CI conditions).**

---

## Final verdict

**CODE READY FOR AWS STAGING**, with one caveat: every P0/P1 finding from the audit is fixed, tested against a live database and a compiled production build, and does not regress any existing behavior. Build, typecheck, the full test suite, Prisma migrations, and OpenAPI validation are all green. The one item keeping the CI *workflow* itself from going fully green end-to-end is the pre-existing lint debt described above (`lib/errors.ts`, `middleware/error-handler.ts`, `services/payouts.ts`) — it predates this remediation, is unrelated to any audited finding, and touching those files was out of this pass's scope. It does not affect runtime correctness or security and can be cleaned up as a small, separate, low-risk follow-up (replacing `any` with concrete types) whenever convenient before or shortly after staging.
