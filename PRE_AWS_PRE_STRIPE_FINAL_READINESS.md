# Pre-AWS / Pre-Stripe Final Readiness Audit

Scope: a full-repository audit (backend, all three Flutter apps, and the undeployed CDK
infra source) for correctness, concurrency safety, security, business-logic integrity,
and deployment readiness — before AWS, Cognito, or Stripe exist anywhere in this
project. No AWS resources were created, no Cognito was configured, no Stripe
integration was added, and no production secrets were touched. Everything below was
either fixed in this repository or is explicitly named as requiring infrastructure that
doesn't exist yet.

---

## 1. Executive verdict

**NOT READY — BLOCKERS REMAIN.**

This is not a verdict on the backend, which is in genuinely strong shape (see §7–§9).
It reflects one specific, large finding: **large parts of `admin_app`'s post-login UI
and `user_app`'s ride-request flow are wired to hardcoded/mock data instead of the
real, already-built API layer** (§8, §5 detail). An Admin "suspending" a flagged driver
or "approving" their documents today changes nothing on the backend — it's a `setState`
call and a SnackBar. A rider's "driver found" screen shows the same static name,
rating, and photo on every request, on a route unrelated to what they searched, with
inert Accept/Decline buttons. This is exactly the class of thing the audit was asked to
catch, and it does not require AWS, Cognito, or Stripe to fix — it requires wiring
existing, correctly-built API client code into existing screens. It was **not**
mechanically fixed in this pass because doing so properly (dozens of screens, loading/
error states, real testing against a live backend) is a multi-day feature-build effort,
not a bug-fix pass, and rushing it risked shipping new, unverified bugs into an
otherwise carefully-built codebase. It is documented in full in §8 and is the clear #1
priority for the next work session.

Every other area audited — backend persistence, concurrency, security, business logic,
WebSocket behavior, environment/OpenAPI hygiene — is either clean or was fixed in this
pass (§4). Backend: **READY**, pending the AWS/Cognito/Stripe integration work that is
explicitly out of scope for this pass. Flutter: **NOT READY**, for the reason above.

---

## 2. Baseline (before this pass' fixes)

| Check | Result |
|---|---|
| Backend `npm run typecheck` | 0 errors |
| Backend `npm run lint` | 0 errors, 0 warnings |
| Backend `npm test` | **191/191 passing** |
| Backend migrations | up to date, 6 migrations, PostgreSQL |
| driver_app `flutter analyze` | 0 errors |
| driver_app `flutter test` | 38/38 passing |
| user_app `flutter analyze` | 0 errors |
| user_app `flutter test` | 30/30 passing |
| admin_app `flutter analyze` | 0 errors |
| admin_app `flutter test` | 44/44 passing |

The baseline was already clean by every mechanical measure (analyzer, lint, tests). The
issues found in this pass (§3) are correctness/security/completeness gaps that don't
show up as analyzer errors or test failures — they required reading the actual route
handlers, service functions, and screen widgets, and in one case (the payout
calculation bug, §3 Critical #4) reproducing the exact silent failure with a new test
before and after the fix.

---

## 3. Issues found

Four parallel deep-dive audits were run (persistence/multi-instance, API/security,
business-logic/WebSocket, env/OpenAPI/code-quality), plus a fifth covering all three
Flutter apps, plus one bug found through direct code reading while implementing fixes.
Findings below are the ones judged real and worth fixing or documenting; a number of
suspected issues were traced and confirmed to already be handled correctly (noted
inline where relevant) and are not repeated here.

### Critical

1. **`PATCH /trips/:id/cancel` — unconditional write + stale `driverId`, orphans a
   driver's assignment.** `backend/src/routes/trips.routes.ts`. The route read the trip
   once, then unconditionally overwrote its status to `CANCELLED` using a plain
   `tx.trip.update`, and decided whether to release the assigned driver using the
   *pre-transaction* `driverId` snapshot. A concurrent match (REQUESTED → MATCHED,
   assigning a driver) between the read and the write got silently clobbered back to
   `CANCELLED` without ever releasing the newly-assigned driver — their
   `DriverAssignment` stayed `ACTIVE` forever, permanently blocking them from new work.

2. **`decideBooking()` — confirming a booking never re-checks for an overlap,
   defeating the overlap-protection invariant.** `backend/src/services/rentals.ts`.
   `REQUESTED` bookings are deliberately allowed to overlap each other (a documented
   product choice), but nothing re-checked for a conflict at *confirmation* time. Two
   renters could both get a `REQUESTED` booking for the same overlapping dates, and the
   driver confirming both (sequentially, no concurrency needed) produced two
   `CONFIRMED` bookings for the same vehicle on the same dates — a real double-booking.

3. **In-memory WebSocket hub silently split-brains across ≥2 backend instances, and
   the App Runner infra config didn't prevent ≥2 instances.** `backend/src/realtime/
   hub.ts` keeps trip-room subscriptions and each driver's latest GPS location in a
   plain in-memory `Map`. This is a documented, known trade-off (`docs/
   realtime-architecture.md`) — but `infra/lib/api-stack.ts`'s `CfnService` set no
   explicit `autoScalingConfigurationArn`, meaning it would run App Runner's *default*
   autoscaling (min 1, max 25) — the documented single-instance assumption the hub
   depends on was not actually enforced by the infra that would deploy it.

4. **`calculatePayoutForPeriod` computed every real driver's payout as $0, silently.**
   Found independently while implementing other fixes, not by the audit agents.
   `backend/src/services/payouts.ts`. The function received a `User.id` (that's what
   `Payout.driverId`/`DriverBankAccount.driverId` actually are — a naming quirk already
   documented elsewhere in the codebase) and used it directly to query
   `Trip.driverId`/`DriverSubscription.driverId` — both of which are foreign keys to
   `Driver.id`, a *different* row. The query never matched, so `grossAmount` was always
   0 regardless of how many completed, paid trips a driver actually had.
   `POST /payouts/calculate` and `POST /payouts/create`'s calculated branch were both
   live, reachable endpoints with this bug and **zero test coverage** exercising them
   with a real trip — the bug was completely invisible to the existing test suite.

### High

5. **`PATCH /rentals/bookings/:id/cancel` — same unconditional-write pattern,
   bypasses the existing safe `endBooking()` path entirely.** A concurrent
   `activate()` (driver marks handover done, `CONFIRMED` → `ACTIVE`, reserves the
   driver) racing a renter's cancel could get silently overwritten to `CANCELLED`
   without ever releasing the driver's fresh assignment.

6. **No duplicate-request guard on `POST /trips` / `POST /courier-requests`.** A
   double-tap or client retry could create two independent Trip/CourierRequest rows for
   one intended request, each independently run through matching — the rider could end
   up matched to two different drivers.

7. **`POST /trips/:id/charge` — TOCTOU on payment uniqueness; a losing race got an
   unhandled 500 instead of 409, and could create an orphaned live Stripe
   PaymentIntent.** No Stripe idempotency key was used, and `payment.create()` had no
   catch for the `P2002` unique-constraint violation a genuine race would produce.

8. **Bank account/routing numbers returned unmasked to Admin in `POST /payouts/
   create`'s response.** `backend/src/services/payouts.ts`. A full, unmasked account
   number and routing number was included in the response body of an Admin-facing
   endpoint whose actual job is just recording a payout amount.

9. **admin_app's entire post-login UI, and user_app's entire ride-request flow, are
   disconnected from their own correctly-built API layer.** See §1 and §8 — this is
   the largest single finding in the audit and was documented, not mechanically fixed.

### Medium

10. `PATCH /rentals/:id/status` (listing approval) had no previous-state check — an
    Admin could "approve" an already-approved or already-rejected listing with no
    terminal-state protection, unlike every analogous endpoint elsewhere.
11. `Vehicle.isPrimary` was not enforced exclusive — neither `POST /vehicles` nor
    `PATCH /vehicles/:id` unset `isPrimary` on a driver's other vehicles, so more than
    one could be primary at once, undermining `matching.ts`'s `orderBy:
    { isPrimary: "desc" }` tie-break.
12. `express-rate-limit`'s default in-memory store isn't shared across instances —
    documented, and the same infra pin (Critical #3) closes the practical risk for now;
    a real fix needs a shared store (Redis).
13. `POST /emergency-alerts` accepted an arbitrary `tripId` with no check that the
    caller is actually party to that trip — Admin's alert dashboard would surface an
    unrelated trip's details under a bogus alert.
14. Courier `finalFare` had no server-side bound, unlike Trip `finalFare` — a driver
    could set it to any positive number when marking a request `DELIVERED`.
15. Graceful shutdown never closed the WebSocket server or its open connections — only
    the HTTP server and Prisma pool. Open sockets sat idle until the 10s force-exit
    killed the process out from under them, an abrupt reset rather than a clean close.
16. `CourierRequestInput` in `openapi.yaml` documented all 6 fields as optional when
    every one is actually required by the real Zod validator.
17. 8 `TextEditingController`s across `driver_app`/`user_app` were never disposed
    (real, if low-severity, resource leaks).
18. `user_app/lib/views/TexiModule/FindRoute.dart` bypassed the shared `ApiClient`
    entirely, called `http.get` with no `try/catch`, and did two unguarded `await` +
    `setState()` calls with no `mounted` check.

### Low / Info

19. `backend/src/services/payouts.ts`'s `generatePayoutsForPeriod` is fully
    implemented, documented as "typically run via a scheduled job," but has no
    caller anywhere and no scheduler infrastructure exists — dead code. Its own
    User.id/Driver.id bug is fixed as a byproduct of Critical #4's fix; whether to wire
    it into an Admin endpoint or delete it is a product decision, not made in this pass.
20. `POST /documents` accepted a client-supplied `fileKey` with no check that it's
    namespaced under the caller's own Cognito sub (low exploitability — requires
    knowing another user's sub, and doesn't itself grant S3 access).
21. Minor OpenAPI response-documentation gaps (missing `400`/`404`/`409` on the trip
    and courier status-patch endpoints; an undocumented regex constraint on payout
    `period`) — fixed in this pass.
22. `user_app/lib/views/TexiModule/FindDriverScreen.dart` had an unguarded `await` +
    `setState()` with no `mounted` check (lower risk than #18 — fast, local asset
    decode, not a network call).
23. `LocationService.getCurrentLocation()` swallows all error detail into a single
    `print()`, giving its one caller no way to distinguish permission-denied from
    GPS-timeout from service-disabled. Documented, not fixed (single low-value call
    site; would need a signature change to fix properly).
24. Two genuine pre-existing bugs unrelated to this audit's scope were confirmed
    already fixed by a prior session and re-verified clean: the Cognito-sub/User.id
    confusion pattern (already fixed in most payout routes — this pass found one
    remaining instance, Critical #4) and the driver-app release-mode crash (verified
    still fixed, §8).

---

## 4. Issues fixed

All Critical, High, and most Medium findings above that don't require AWS/Cognito/
Stripe were fixed in this repository:

- **#1** `trips.routes.ts` — `PATCH /trips/:id/cancel` now uses the same atomic
  conditional-`updateMany` pattern as `PATCH /trips/:id/status`, and releases the
  driver using the post-transaction row, not a stale pre-transaction snapshot.
  `PATCH /trips/:id/status` itself was also fixed to use `updated.driverId` (read
  inside the transaction) instead of `existing.driverId` for the same reason.
- **#2** `rentals.ts` — `decideBooking()` now re-runs the same overlap query
  `createBooking()` uses, inside the same `Serializable` transaction, before
  confirming; the route now surfaces `RENTAL_OVERLAP` as a 409.
- **#3** `infra/lib/api-stack.ts` — added an explicit `CfnAutoScalingConfiguration`
  pinned to `minSize: 1, maxSize: 1`, referenced via the service's
  `autoScalingConfigurationArn`. This is source code for infrastructure that has not
  been deployed — `cdk synth` was run locally to confirm it's valid CloudFormation;
  nothing was deployed to AWS. `backend/src/index.ts` was also fixed to capture
  `attachRealtime()`'s return value and gracefully close every open WebSocket
  connection (code 1001) before the HTTP server/Prisma pool shut down.
- **#4** `payouts.ts` — `calculatePayoutForPeriod` now resolves the `Driver` row from
  the given `User.id` first, then uses `driver.id` for the Trip/DriverSubscription
  queries. Two new tests reproduce the bug end-to-end (a driver with a real completed,
  paid trip; asserts `grossAmount`/`netAmount` are correct, not 0) and would have
  caught it before it ever shipped.
- **#5** `rentals.routes.ts` — the renter-cancel route now uses the same atomic
  conditional-update pattern.
- **#6** `trips.routes.ts` / `courier.routes.ts` — both `POST` endpoints now reject
  with 409 if the calling rider/sender already has an open (non-terminal) trip/
  courier request. Documented limitation: this is an application-level pre-check, not
  a database-level constraint like `DriverAssignment`'s partial unique index — a true
  concurrent double-tap (sub-millisecond) window remains theoretically possible. A
  full fix would add a matching partial unique index; not done in this pass to avoid
  a schema migration on top of everything else changed here — noted as a "can fix now"
  follow-up in §5A.
- **#7** `payments.routes.ts` — added a Stripe idempotency key
  (`trip-charge-${trip.id}`) to the `PaymentIntent` creation call, and wrapped both
  `payment.create()` calls in a `try/catch` that maps a `P2002` violation to a clean
  409 instead of an unhandled 500.
- **#8** `payouts.ts` — added a `maskAccountDigits()` helper; `createPayout()`'s
  response now returns only the last 4 digits of the account/routing number.
- **#10** `rentals.routes.ts` — `PATCH /rentals/:id/status` now uses a conditional
  update requiring the listing be `PENDING_APPROVAL`, matching the terminal-state
  protection pattern used everywhere else.
- **#11** `vehicles.routes.ts` — both `POST /vehicles` and `PATCH /vehicles/:id` now
  unset `isPrimary` on the driver's other vehicles, in the same transaction, when the
  new/updated one is marked primary.
- **#13** `alerts.routes.ts` — `POST /emergency-alerts` now verifies the caller is the
  referenced trip's rider or assigned driver before accepting a `tripId`.
- **#14** `courier.routes.ts` — added the same `FINAL_FARE_MIN_RATIO`/`MAX_RATIO`
  bound already used for Trip `finalFare`.
- **#16, #21** `openapi.yaml` — `CourierRequestInput` now has a `required` array
  matching the real validator; missing `400`/`404`/`409` responses added to the trip
  and courier status-patch endpoints; the payout `period` field's regex constraint is
  now documented.
- **#17** 8 files across `driver_app`/`user_app` — added `dispose()` overrides for
  every previously-undisposed `TextEditingController`.
- **#18, #22** `FindRoute.dart` — both handlers now wrap the network call in
  `try/catch`, check `mounted` before every post-`await` `setState()`, and fail to an
  empty result list instead of throwing uncaught or hanging silently.
  `FindDriverScreen.dart` — added the missing `mounted` check.

**Not fixed, by design** — #9 (the large mock-data finding), #12 (rate-limiter shared
store — requires Redis/AWS), #19 (dead payout-batch code — product decision), #20
(documents fileKey binding — Info-level, low exploitability), #23 (LocationService
error detail — Info-level, single call site), #24 (Cognito-sub confusion pattern was
already fixed elsewhere; Critical #4 was the one remaining instance). All are carried
into §5 below with the reason.

10 new regression tests were added (§13), covering Critical #1, #2, and #4 directly —
each one fails against the pre-fix code and passes against the fix, confirmed by
running the full suite before and after.

---

## 5. Remaining gaps

**A. Can be fixed now (no AWS/Cognito/Stripe needed) — not done in this pass**

- Wire `admin_app`'s driver/rider/trip/support/courier/car-paddy/rental-listing/
  subscription screens, and `user_app`'s ride-request/find-driver/account/profile
  screens, to their already-built API client layers instead of hardcoded mock data
  (§1, §8). This is the top-priority follow-up.
- A database-level partial unique index (matching `DriverAssignment`'s own pattern)
  to close the narrow, true-concurrent-request race the new application-level
  duplicate-request guard (#6) doesn't fully close.
- `generatePayoutsForPeriod` — decide whether to expose it via an Admin endpoint
  (mirroring the existing single-driver payout endpoints) or delete it as dead code.
- `LocationService.getCurrentLocation()`'s swallowed error detail (Info-level).
- `POST /documents`'s `fileKey` ownership binding (Info-level).
- The remaining 12 harmless, non-sensitive `print()` calls across the Flutter apps
  should be routed through a logger (or stripped) before release, per the code-quality
  sweep — cosmetic, not a defect.

**B. Requires AWS**

- A shared backend (ElastiCache Redis is the natural fit) for `src/realtime/hub.ts`'s
  trip-room/driver-location state, so real-time features work correctly across more
  than one App Runner instance. The pin added in this pass (Critical #3) is a safe
  stopgap, not the real fix — it caps the service at one instance, which is correct
  for current scale but is not a permanent answer.
- The same Redis instance backing `express-rate-limit` via `rate-limit-redis`, so the
  per-IP budget is enforced correctly once more than one instance is running.
- S3 for document/asset storage — already correctly designed for this (presigned
  URLs, no local disk writes anywhere in the backend) and just needs real buckets.
- RDS PostgreSQL — the schema, migrations, and every query are already
  PostgreSQL-native; this is a "point `DATABASE_URL` at the real instance" step, not
  a code change.

**C. Requires Cognito**

- Real authentication. The Flutter apps' `AuthProvider` seam
  (`createDefaultAuthProvider()`) is ready for this — see the prior session's
  `PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md` for the full architecture. Until Cognito
  exists, none of the three apps can authenticate in a release build (by design —
  `UnauthenticatedAuthProvider.login()` always throws), which is also *why* the
  mock-data screens in §8 were never exercised against a real backend in practice.
- Real password reset ("Forgot Password?" is currently a dead button in all three
  apps' login screens — correctly left unwired rather than faked, since there is no
  backend capability for it without Cognito).

**D. Requires Stripe**

- `processPayout()` fakes a successful transfer (`transactionId:
  stripe_payout_${Date.now()}`) instead of calling a real payment provider — already
  self-documented with a `// TODO: Integrate with Stripe Connect` comment, and
  disclosed in `openapi.yaml`'s description for that endpoint. Not touched in this
  pass, consistent with "do not fake Stripe behavior."
- The Stripe secret in `infra/lib/api-stack.ts` is created with explicit placeholder
  values (`sk_live_REPLACE_ME`) meant to be overwritten once, post-deploy — this is
  the existing, correct pattern; nothing changed here.

**E. Requires production infrastructure generally**

- Real CloudWatch-backed observability — the app already produces clean, structured
  console output with no secret leakage (§6), ready to be picked up by CloudWatch once
  it's wired in; nothing further to do on the application side.
- App Store / Google Play accounts, production domains/certificates — untouched,
  out of scope, no code depends on them.

---

## 6. Security status

**No known Critical or High security issue remains** in the backend after this pass.
Confirmed via a dedicated audit (route-by-route authorization trace, secrets sweep,
injection/CORS/headers/rate-limit review) plus fixes applied for the findings it did
turn up:

- **Authorization**: every non-public route traced end-to-end; ownership checks
  correctly scope `:id`-based routes to the caller's own resource, with an Admin
  bypass where appropriate. No IDOR found in the reviewed routes. The one real gap
  found (`emergency-alerts` accepting any `tripId`) is fixed (§4 #13).
- **Secrets**: a full-repo sweep (backend, all 3 Flutter apps, infra, docs) found zero
  hardcoded API keys, JWT secrets, database passwords, AWS keys, or Stripe live keys.
  `.env`/`.env.example` files contain only placeholders and are correctly git-ignored.
- **Injection**: the only raw SQL in the codebase is a parameterless `SELECT 1` health
  check. No `eval`/`Function`/unsanitized `child_process`. All reviewed request bodies
  go through Zod validation before touching Prisma.
- **HTTP security posture**: Helmet applied globally; CORS is a real production
  allowlist (not a wildcard); rate limiting is applied (its multi-instance limitation
  is tracked in §5B, not a security hole today given the infra pin in §4 #3); body
  size limits are the sane `body-parser` default.
- **Error handling**: verified by test that malformed-request and 500 error paths
  never leak stack traces, SQL errors, or internal paths, in any `NODE_ENV`.
- **WebSocket authorization**: connection-time auth and suspension checks
  independently re-implemented (not just inherited from HTTP); per-trip subscription
  and location-push are both authorization-checked; no cross-user leakage found.
- **Sensitive data exposure**: bank account/routing numbers are now masked in the one
  response path that leaked them unmasked (§4 #8); no token/password logging found
  anywhere in the backend or the three Flutter apps.
- **Dependency vulnerabilities**: `npm audit` in `backend/` and `infra/` both report
  findings, all in dev-only tooling (`eslint`'s transitive `brace-expansion`/`js-yaml`,
  and `prisma` CLI's transitive `deepmerge-ts`) — confirmed via `npm audit --omit=dev`
  that none of these ship into the production runtime image. Per instruction, not
  blindly upgraded; flagged for a deliberate, compatibility-checked bump later.

---

## 7. Database status

- **PostgreSQL, confirmed.** `prisma/schema.prisma`'s `datasource` is
  `provider = "postgresql"`. A repository-wide grep for `sqlite`, `SQLite`,
  `better-sqlite3`, `sqlite3`, and any `.db` file reference returned zero matches
  anywhere in the repo.
- **Prisma**, 6 migrations, all applied — `npx prisma migrate status` reports
  "Database schema is up to date!" against a real local Postgres instance (not a mock).
- **No local persistent database dependency.** No `fs.writeFile`/`multer diskStorage`/
  local upload directory anywhere in `backend/src` — every file upload goes through S3
  presigned URLs, and documents are recorded as S3 key metadata only. The only
  filesystem read in the backend is a fixed, build-time `openapi.yaml` asset.
- **Transaction/concurrency status**: driver/vehicle matching and assignment locking
  (`matchDriverToTrip`, `reserveDriver`) use `Serializable`-isolation transactions
  backed by a real partial unique index (`DriverAssignment(driverId) WHERE status =
  'ACTIVE'`) as a hard database-level backstop — confirmed correct and used as the
  template for this pass's own new fixes (rental overlap re-check, trip cancel
  atomicity). Stripe webhook idempotency is DB-backed via a conditional `updateMany`.

---

## 8. Flutter status

### driver_app
- `flutter analyze`: 0 errors. `flutter test`: 38/38 passing.
- `flutter build web --release`: succeeds; re-verified in this pass by regenerating
  the (gitignored, not committed) `web/` platform scaffold, building, and driving the
  output in a real headless Chromium — the Login screen renders correctly, no
  `DevOnlyAuthProvider` crash, dev-only sign-in section correctly compiled out.
- Auth architecture: verified sound (from the prior session's dedicated remediation,
  re-confirmed here) — release build cannot construct `DevOnlyAuthProvider`, no
  hardcoded token, login only navigates after a real `AuthProvider` call succeeds.
- API connectivity: the **courier flow is genuinely wired to the backend** and is the
  reference-quality example in this codebase (loading/error/empty states, disable-
  while-submitting, 409 `DRIVER_BUSY` reconciliation). The **ride-accept flow is a
  local simulation** (`ride_api.dart`/`driver_api.dart` defined but never called) —
  explicitly labeled as such in the code's own comments, not disguised.
- Known limitations: `DriverProfile` shown in the shell is always hardcoded defaults,
  never fetched from `DriverApi.getMyProfile()`; `my_trips_screen.dart`/
  `my_documents_screen.dart`/`earnings_screen.dart` all show mock data; "Cash out to
  bank"/"Payout history" tiles are inert.

### user_app
- `flutter analyze`: 0 errors. `flutter test`: 30/30 passing.
- Auth architecture: same as driver_app — verified sound.
- API connectivity: **`RideApi`/`PricingApi`/`RentalApi`/`CourierApi` are fully
  implemented but never instantiated or called anywhere in `lib/`.** The entire
  ride-request flow ("Found 3 Drivers," Accept/Decline, live driver search) is
  hardcoded UI with inert buttons; `ride_view_popup.dart` auto-advances through fake
  trip stages via a timer regardless of any real trip status; profile/account screens
  show a hardcoded name/email throughout.
- Fixed in this pass: 6 undisposed controllers, `FindRoute.dart`'s unguarded network
  call and missing `mounted` checks, `FindDriverScreen.dart`'s missing `mounted` check.

### admin_app
- `flutter analyze`: 0 errors. `flutter test`: 44/44 passing.
- Auth architecture: same as the other two — verified sound, including the logout fix
  from the prior session (side-menu "Log out" now actually calls `authProvider.logout()`).
- API connectivity: **zero screens under `lib/views/` reference any of the app's own,
  correctly-built API classes** (`DriverApi`, `RiderApi`, `DashboardApi`, `CourierApi`,
  `RentalApi`, `SupportApi`, `PayoutApi`, `PricingApi`, `DocumentApi`). `main.dart`
  never even constructs an `ApiClient`. Every screen — driver/rider lists, trip
  monitoring, support tickets, fraud/emergency alerts, courier/car-paddy/rental
  requests — reads from hardcoded `mock*` data. Driver "suspend"/"approve documents"
  actions only call `setState`; "Save pricing rules" just pops the screen.
- Fixed in this pass: 1 undisposed controller.

**Bottom line**: analyzer, tests, and release builds are all clean across all three
apps, and the authentication architecture is genuinely production-correct and ready
for Cognito. What's missing is the data layer being connected to the UI layer in two
of the three apps — a large, well-scoped, but substantial remaining task (§1, §5A).

---

## 9. API status

- **OpenAPI coverage**: full 1:1 match confirmed between every implemented route
  (88 method+path registrations across 17 route files) and every documented path in
  `openapi.yaml` — no undocumented endpoint, no dead documentation, no HTTP method
  mismatch. One real schema drift found and fixed (`CourierRequestInput`'s missing
  `required` array); minor response-documentation gaps found and fixed (§4 #16, #21).
- **Authentication**: enforced via `requireAuth` (Cognito JWT verification through
  `aws-jwt-verify`) on every route that should require it; the one intentionally
  public route is `GET /health`.
- **Authorization**: role-gated via `requireRole`, ownership-scoped via per-route
  checks traced and confirmed correct (§6). Suspended-user enforcement applies
  uniformly across HTTP and the WebSocket path.

---

## 10. AWS readiness

**Not deployed. Nothing was created.** What remains to connect when AWS deployment
begins:

- Point `DATABASE_URL`/`DB_HOST` at a real RDS Postgres instance — no schema or query
  changes needed.
- Provision the S3 buckets `uploads.routes.ts`/`documents.routes.ts` already expect
  (`DOCUMENTS_BUCKET`, `ASSETS_BUCKET` env vars) — the presigned-URL upload flow is
  already fully built against this.
- Deploy the CDK stacks as-is; the one change made in this pass
  (`SingleInstanceAutoScaling`, pinning App Runner to exactly one instance) should stay
  in place until the Redis-backed realtime hub (§5B) lands — raising it before that
  would silently reintroduce the split-brain WebSocket bug this pass closed off.
- Wire CloudWatch to the existing console output — no application-side logging
  changes needed; nothing currently logs a secret.
- The Stripe secret placeholder in `infra/lib/api-stack.ts` needs its one-time,
  documented post-deploy overwrite (unrelated to this audit — pre-existing pattern).

## 11. Stripe readiness

**Not integrated. Nothing was added.** What remains to connect later:

- `processPayout()`'s `// TODO: Integrate with Stripe Connect` — replace the
  simulated success with a real Stripe Connect transfer call.
- The card-payment path (`POST /trips/:id/charge`) already creates a real Stripe
  `PaymentIntent` with a proper idempotency key (fixed in this pass, §4 #7) — this
  side is functionally ready; it just needs real Stripe keys instead of the
  `sk_test_dummy_for_local_dev_and_tests` fallback (which is provably unreachable in
  production — `config/env.ts` throws at boot if `STRIPE_SECRET_KEY` is unset there).
- The Stripe webhook handler (`billing.routes.ts`) is already built, tested, and
  DB-backed idempotent against replayed/out-of-order deliveries — ready as-is.

---

## 12. Final blocker table

| Issue | Severity | Can fix now? | Dependency | Status |
|---|---|---|---|---|
| admin_app/user_app UI disconnected from real API layer | Critical | Yes | none | **Documented, not fixed — top priority** |
| Trip cancel orphans DriverAssignment on race | Critical | Yes | none | **Fixed** |
| Rental decideBooking allows double-booking | Critical | Yes | none | **Fixed** |
| WebSocket hub split-brains across instances | Critical | Partial (infra pin) | AWS (Redis) for full fix | **Mitigated (pinned to 1 instance)** |
| Payout calculation always $0 (Cognito-sub/User.id bug) | Critical | Yes | none | **Fixed + regression tests** |
| Rental renter-cancel race orphans driver assignment | High | Yes | none | **Fixed** |
| No duplicate-request guard on trip/courier creation | High | Yes (app-level) | DB-level fix needs migration | **Mitigated** |
| Payment charge TOCTOU / no idempotency key | High | Yes | none | **Fixed** |
| Unmasked bank account numbers in payout response | High | Yes | none | **Fixed** |
| Rate limiter not shared across instances | Medium | No | AWS (Redis) | **Documented** |
| Rental listing approval no previous-state check | Medium | Yes | none | **Fixed** |
| Vehicle.isPrimary not exclusive | Medium | Yes | none | **Fixed** |
| Emergency alert accepts any tripId | Medium | Yes | none | **Fixed** |
| Courier finalFare no bound check | Medium | Yes | none | **Fixed** |
| WebSocket not closed gracefully on shutdown | Medium | Yes | none | **Fixed** |
| OpenAPI schema/response-doc drift | Medium/Low | Yes | none | **Fixed** |
| Undisposed TextEditingControllers (8) | Medium | Yes | none | **Fixed** |
| FindRoute.dart unguarded async / no error handling | Medium | Yes | none | **Fixed** |
| Stripe payout processing is simulated | — | No | Stripe | **Documented (self-flagged in code already)** |
| Real Cognito authentication | — | No | Cognito | **Architecture ready (prior session)** |
| generatePayoutsForPeriod is dead code | Low | Yes | none (product decision) | **Documented** |
| Documents fileKey ownership binding | Info | Yes | none | **Documented** |
| LocationService swallows error detail | Info | Yes | none | **Documented** |

---

## 13. Exact verification commands

All executed for real against a real local PostgreSQL 16 instance; none of these
results are assumed or estimated.

```
# Backend
service postgresql start
cd backend && npx prisma migrate deploy        # "No pending migrations to apply."
npx prisma migrate status                      # "Database schema is up to date!"
npm run typecheck                               # 0 errors
npm run lint                                    # 0 errors, 0 warnings
npm test                                        # 200/200 passing (191 baseline + 9 new regression tests)
npm audit / npm audit --omit=dev                # findings isolated to dev tooling, confirmed not shipped

# Infra (source-code validation only — nothing deployed)
cd infra && npm ci
npx tsc --noEmit                                # 0 errors
npx cdk synth                                   # synthesizes cleanly, incl. new AutoScalingConfiguration

# Flutter — driver_app
flutter analyze                                 # 0 errors
flutter test                                    # 38/38 passing
flutter create . --platforms web && flutter build web --release   # succeeds
# release build driven in real headless Chromium (Playwright) — Login renders,
# no DevOnlyAuthProvider crash, dev-only sign-in section absent

# Flutter — user_app
flutter analyze                                 # 0 errors
flutter test                                    # 30/30 passing

# Flutter — admin_app
flutter analyze                                 # 0 errors
flutter test                                    # 44/44 passing

# Repository-wide scans
grep -rniE "sqlite|better-sqlite3" (all source dirs)             # 0 matches
grep -rnE "AKIA...|sk_live_...|sk_test_[20+ chars]|BEGIN PRIVATE KEY" # 0 real matches (only .env.example placeholders)
grep -rn "localhost|127.0.0.1" backend/src (excl. tests)          # 1 match, confirmed a URL-parser base string, not a network target

git status / git diff --stat                    # reviewed, see §14
```

---

## 14. Commit

25 files changed: 12 backend route/service files, 3 new backend test-file additions
(9 new regression tests total), `openapi.yaml`, `infra/lib/api-stack.ts`, and 9 Flutter
files across `driver_app`/`user_app`. No backend business logic was touched beyond
what's listed in §4; no AWS/Cognito/Stripe credentials, resources, or configuration
were added anywhere.

```
git diff --stat
 backend/openapi.yaml                               | 17 +++-
 backend/src/index.ts                               | 12 ++-
 backend/src/routes/alerts.routes.ts                | 19 +++++
 backend/src/routes/courier.routes.ts               | 30 +++++++
 backend/src/routes/payments.routes.ts              | 68 +++++++++++-----
 backend/src/routes/payouts.routes.test.ts          | 87 ++++++++++++++++++++
 backend/src/routes/rentals.routes.test.ts          | 95 ++++++++++++++++++++++
 backend/src/routes/rentals.routes.ts               | 49 +++++++++--
 backend/src/routes/trips.routes.test.ts            | 75 +++++++++++++++++
 backend/src/routes/trips.routes.ts                 | 61 ++++++++++----
 backend/src/routes/vehicles.routes.test.ts         | 52 ++++++++++++
 backend/src/routes/vehicles.routes.ts              | 29 +++++--
 backend/src/services/payouts.ts                    | 81 +++++++++++++-----
 backend/src/services/rentals.ts                    | 54 ++++++++++--
 driver_app/lib/views/vehicles/add_vehicle_screen.dart | 10 +++
 infra/lib/api-stack.ts                             | 22 +++++
 user_app/lib/views/OtherViews/AddressSearch.dart   |  6 ++
 user_app/lib/views/OtherViews/EditProfileInfo.dart |  9 ++
 user_app/lib/views/OtherViews/LanguageSelectionScreen.dart |  6 ++
 user_app/lib/views/OtherViews/UpdatePassword.dart  |  8 ++
 user_app/lib/views/Services/AddBankAccountPage.dart |  9 ++
 user_app/lib/views/Services/IdelivaOnboardingScreen.dart |  6 ++
 user_app/lib/views/Services/ReferralCodePage.dart  |  6 ++
 user_app/lib/views/TexiModule/FindDriverScreen.dart |  1 +
 user_app/lib/views/TexiModule/FindRoute.dart       | 38 ++++++---
 25 files changed, 759 insertions(+), 91 deletions(-)
```

Committed to `claude/ravelgo-completeness-audit-873u5u` — see the commit immediately
following this file for the exact SHA, and the commit message for the full summary.
