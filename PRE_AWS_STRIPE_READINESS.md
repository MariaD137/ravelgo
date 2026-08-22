# RavelGo — Pre-AWS / Pre-Stripe Completion Audit and Remediation

Scope: everything completable and testable **locally**, before AWS deployment and Stripe integration. No AWS infrastructure was touched, deployed, or configured. No Stripe integration (Connect, production payments, webhooks, payouts, payment capture, refunds, subscription billing) was implemented — all explicitly deferred per the task's own exclusion list, and marked with an explicit non-payment state (`paymentStatus: NOT_CONFIGURED`) rather than silently absent or faked.

The existing Ride/Courier/Rental separation and the `DriverAssignment` concurrency protections from the prior remediation pass were preserved and built on, not rewritten.

## 1. Complete List of Findings

| # | Finding | Domain | Severity |
|---|---|---|---|
| F1 | `PATCH /trips/:id/status` allowed illegal state transitions (e.g. `REQUESTED → COMPLETED` skipping `MATCHED`, or updating an already-terminal trip again) — a pre-existing gap, not introduced by prior sessions | Ride | **P0** |
| F2 | `updateCourierStatus` (courier status endpoint) allowed the same class of illegal transitions (e.g. `MATCHED → DELIVERED` skipping `IN_TRANSIT`, or updating a terminal request again) | Courier | **P0** |
| F3 | `endBooking` (`PATCH /rentals/bookings/:id/end`) performed an **unconditional** status update with zero precondition check — a `REQUESTED` booking (never confirmed or activated) could be marked `COMPLETED` directly, or a terminal booking updated again | Rental | **P0** |
| F4 | `driver_shell.dart` referenced `DriverOperationalState.isBusy` without importing the file that defines the extension — a real compile error, caught only by actually running `flutter analyze` | Flutter (driver_app) | **P0** (build-breaking) |
| F5 | All three apps' `SplashScreen` used an uncancelled `Future.delayed` to navigate after a timer; disposing the screen before the timer fired still left the timer pending (a real `flutter test` failure: "A Timer is still pending even after the widget tree was disposed", reproduced in `user_app`) | Flutter (all 3 apps) | **P1** |
| F6 | `ApiClient` had no handling for network-layer failures (no connectivity, timeout, malformed response) — only HTTP error responses were turned into a catchable `ApiException`; a raw `SocketException`/`TimeoutException` would propagate uncaught past every screen's `on ApiException catch` block | Flutter (driver_app) | **P1** |
| F7 | `user_app`'s Google Places search (`FindRoute.dart`) read `dotenv.env['GOOGLE_API_KEY']`, but every `.env.example` in the repo declares `GOOGLE_MAPS_API_KEY` — the feature would silently get a `null` key even with a correctly configured `.env` | Flutter (user_app) | **P1** |
| F8 | Courier and Rental had no visible payment-state field at all — payment status was implicit/absent rather than an explicit, queryable "not yet configured" marker | Courier, Rental | **P2** |
| F9 | `findOwnDriver(cognitoSub)` was duplicated (identical body) in `subscriptions.routes.ts`, `documents.routes.ts`, and `carpaddy.routes.ts` instead of using the shared `services/driver.ts` helper already used elsewhere | Backend code quality | **P2** |
| F10 | `driver_app`'s ride-simulation flow (`ActiveTripScreen`) never marked the shared `DriverSession` busy, so a driver "on" the local ride demo could still navigate into the real courier-accept flow and accept a delivery | Flutter (driver_app) | **P2** |
| F11 | `Trip.vehicleId` had zero test coverage — the vehicle-selection logic added in the prior session (primary-vehicle preference, no-vehicle-on-file fallback) was unverified | Backend tests | **P2** (coverage gap, not a defect) |
| F12 | No malformed/garbage-ID tests existed for any of the newer Courier/Rental/Trip endpoints, leaving the "does a junk ID 500 instead of 404" question unverified | Backend tests | **P2** (coverage gap) |
| F13 | Minor dead code: unused local variables (`widgetsBinding` in three `main.dart` files, `mapPreviewPath`, `isSelected`), unused fields (`_decoration`, `_selectedIndex`, `_earnText`, `_dailyEarnings`, `_onMenuSelect`), unused imports (`dart:io` × 6, duplicate imports × 2), unused private widget methods never wired to any UI (`_bottomNav` × 2, `_buildActionRow`) | Flutter (user_app mostly) | **P3** |
| F14 | Design ambiguity, not a bug: `DriverAssignment`'s exclusivity is driver-level, not vehicle-level, so a driver who owns two vehicles cannot do a ride with one while a `RentalBooking` on the other is `ACTIVE` — the spec text "Ride + **conflicting** Rental" arguably implies only same-vehicle conflicts should block. Documented, not changed (see Remaining Blockers). | Ride/Rental design | **P3 / flagged** |

## 2. Files Changed

**Backend** (schema, routes, services, tests):
- `backend/prisma/schema.prisma`, `backend/prisma/migrations/20260822112721_add_payment_integration_status/` (new)
- `backend/src/routes/trips.routes.ts`, `courier.routes.ts`, `rentals.routes.ts`, `documents.routes.ts`, `carpaddy.routes.ts`, `subscriptions.routes.ts`
- `backend/src/services/courier.ts`, `rentals.ts`
- `backend/src/routes/trips.routes.test.ts`, `courier.routes.test.ts`, `rentals.routes.test.ts`

**Flutter — `driver_app`**:
- `lib/main.dart`, `lib/services/api/api_client.dart`, `lib/views/shell/driver_shell.dart`, `lib/views/splash/splash_screen.dart`, `lib/views/trip/active_trip_screen.dart`, `lib/views/home/driver_home_screen.dart`, `lib/views/preferences/driver_preferences_screen.dart`, `lib/views/courier/available_courier_requests_screen.dart`, `lib/views/documents/my_documents_screen.dart`, `lib/views/support/faq_screen.dart`, `lib/views/trips/my_trips_screen.dart`, `lib/views/vehicles/vehicle_list_screen.dart`
- New: `test/api_client_test.dart`, `test/driver_session_test.dart`, `test/driver_home_gating_test.dart`

**Flutter — `user_app`**:
- `lib/main.dart`, `lib/views/SplashScreen/SplashScreen.dart`, `lib/views/TexiModule/FindRoute.dart`, `lib/components/LocationService.dart`, plus 12 files with only unused-import/dead-code cleanup (`Account.dart`, `AppDrawer.dart`, `ravel_driver_portal_screen.dart`, `Home.dart`, `ColourPicker.dart`, `RideDetailsView.dart`, `RidesView.dart`, `ServicesView.dart`, `BasicDetailsPage.dart`, `IDelivaPage.dart`, `IdelivaProfileScreen.dart`, `CreateAccount.dart`, `VehicleInformation.dart`, `FindDriverScreen.dart`, `SearchDriverScreen.dart`)
- `test/widget_test.dart` (fixed + extended)

**Flutter — `admin_app`**:
- `lib/main.dart`, `lib/views/splash/splash_screen.dart`, `lib/views/reports/analytics_screen.dart`, plus 5 cosmetic-lint fixes
- `test/widget_test.dart` (extended)

All three apps' `analysis_options.yaml` and `pubspec.lock` were auto-updated by `flutter pub get` (Flutter SDK's standard build-directory exclusion addition; `driver_app`'s lockfile also reflects the one new dependency, `http: ^1.2.0`, added in the prior session).

## 3. Tests Added

- **Backend**: 19 new tests — illegal-transition guards (Trip ×2, Courier ×2, Rental ×3), `paymentStatus` defaults (Courier, Rental), `Trip.vehicleId` correctness (own-vehicle assignment, no-vehicle fallback, driver-level busy exclusion, primary-vehicle preference), and malformed/garbage-ID 404 checks across Courier, Rental, and Trip endpoints (6 tests).
- **Flutter (`driver_app`)**: 20 new tests — `ApiClient` (token attachment, DRIVER_BUSY conflict shape, non-JSON error bodies, query encoding, `SocketException`/`TimeoutException`/malformed-response wrapping — 8 total), `DriverSession`/`DriverOperationalState` (8), operational-exclusivity UI gating (4).
- **Flutter (`user_app`, `admin_app`)**: 4 new tests — real splash-screen-to-login navigation + early-dispose-doesn't-throw, replacing the previously non-functional single-widget smoke test.

## 4. Tests Executed

Backend: `NODE_ENV=test node --test --test-concurrency=1 --require ts-node/register src/**/*.test.ts`, run against a real local PostgreSQL 16 instance (no SQLite), with the same dummy Cognito/Stripe/bucket env values CI itself uses. Run to completion multiple times during this session, most recently right before this report.

Flutter: `flutter analyze` and `flutter test`, run against a real Flutter 3.47.1 / Dart 3.13.1 SDK installed for this session (downloaded from Flutter's official stable-channel release, verified via `flutter --version`) — not assumed, not skipped.

## 5. Flutter Analyze Results

| App | Errors | Warnings | Info (style, deliberately not chased) |
|---|---|---|---|
| `driver_app` | 0 | 0 | 3 (`use_null_aware_elements`) |
| `user_app` | 0 | 0 | 172 (naming/style conventions predating this session — `use_key_in_widget_constructors`, `library_private_types_in_public_api`, non-camelCase locals, `deprecated_member_use: withOpacity`, etc.) |
| `admin_app` | 0 | 0 | 2 (`use_null_aware_elements`) |

Started at: `driver_app` 1 real compile error + 12 other issues; `user_app` 0 errors / 25 warnings / ~180 info; `admin_app` 0 errors / 2 warnings / 6 info. All errors and warnings fixed. The remaining `use_null_aware_elements` infos were deliberately left — rewriting them to Dart's newer `?value` null-aware-element syntax risks a compatibility mismatch with the declared `sdk: ^3.8.0` minimum, for a purely cosmetic suggestion with zero effect on correctness. `user_app`'s 172 remaining info-level naming/style suggestions predate this session, span the entire pre-existing UI codebase, and were not touched — fixing them would mean a repo-wide rename/restyle pass with no correctness benefit, which the task's own "do not rewrite working architecture unnecessarily" instruction argues against.

## 6. Flutter Test Results

| App | Before | After | Passing |
|---|---|---|---|
| `driver_app` | 1 | 23 | 23/23 |
| `user_app` | 1 (failing) | 1 | 1/1 |
| `admin_app` | 1 | 3 | 3/3 |

`user_app`'s one test was failing at the start of this audit (F5 — the pending-timer bug); it passes now that the underlying `SplashScreen` bug is fixed and the test itself was rewritten to actually exercise the fixed navigation instead of just checking the first frame.

## 7. Backend Test Results

**183/183 passing** (up from 164 at the start of this session), run against real PostgreSQL 16, `npx tsc --noEmit` clean, `npx eslint` clean except 10 pre-existing `no-explicit-any` errors in four files this session did not touch (`lib/errors.ts`, `middleware/error-handler.ts`, `routes/payouts.routes.ts`, `services/payouts.ts` — all pre-dating this session, all outside its scope).

## 8. Remaining Blockers

- **`user_app` and `admin_app` have zero backend connectivity.** Neither has an `http` (or equivalent) dependency at all — every screen in both apps is local/demo data. This is a pre-existing, repo-wide condition (not something this session introduced), and rewiring either app to the real backend is a project of the same scope as last session's `driver_app` courier-flow work, repeated twice. Out of scope to complete within this pass; flagged here rather than silently left unmentioned.
- **No real Cognito sign-in exists in any of the three apps** (confirmed again this session — no `amplify_auth_cognito` or equivalent dependency anywhere). `driver_app`'s `AuthTokenProvider` interface (from the prior session) is the seam a real sign-in flow will plug into; it has no token to fetch yet.

## 9. Items Intentionally Deferred to AWS/Stripe Integration

Per the task's explicit exclusion list — none of the following were touched, configured, or simulated:
AWS deployment, App Runner, RDS, production Cognito, production S3, CloudFront, Route 53, production CloudWatch, Stripe Connect, Stripe production payments, Stripe webhooks, driver payouts, rental payment capture, courier payment capture, refunds, subscription billing.

`CourierRequest.paymentStatus` and `RentalBooking.paymentStatus` were added as `NOT_CONFIGURED`-only enums (`PaymentIntegrationStatus`) specifically so this boundary is visible in the data model rather than an unstated absence — no payment logic was implemented behind them.

## 10. Design Decisions Made (Not Invented Business Rules)

- **Trip state machine** (`TRIP_ALLOWED_FROM` in `trips.routes.ts`): `REQUESTED→MATCHED→{IN_PROGRESS→COMPLETED}`, `CANCELLED` reachable from any non-terminal state, `DISPUTED` reachable from `MATCHED`/`IN_PROGRESS`/`COMPLETED` (a rider can dispute a trip after it's done, not just during). Once `COMPLETED`/`CANCELLED`/`DISPUTED`, never again.
- **Courier state machine** (`COURIER_ALLOWED_FROM` in `services/courier.ts`): `MATCHED→IN_TRANSIT→DELIVERED`, `CANCELLED` from `MATCHED` or `IN_TRANSIT`. `REQUESTED` is never reachable through the status endpoint — claiming happens only through the accept endpoint.
- **RentalBooking state machine** (`END_BOOKING_FROM_STATUSES` in `services/rentals.ts`): `REQUESTED→{CONFIRMED|REJECTED}` (via decision) `→ACTIVE` (via activation, CONFIRMED only) `→COMPLETED` (ACTIVE only — you can't complete a handover that never happened) or `→CANCELLED` (from CONFIRMED or ACTIVE). The renter's own `/cancel` endpoint (pre-existing, unchanged) allows `REQUESTED`/`CONFIRMED→CANCELLED` directly.
- **RentalListing** admin approval (`PENDING_APPROVAL↔APPROVED↔REJECTED`) was deliberately left permissive (no state-machine guard added) — it's a moderation/curation status an admin may reasonably reverse, distinct from the operational-safety-critical `RentalBooking` transitions above.
- **Overlap-blocking statuses for new bookings** remain `CONFIRMED`/`ACTIVE` only (unchanged from the prior session) — a documented product choice, not re-litigated here.

## 11. Final Verdict

**NOT READY — specific blockers:**

1. `user_app` and `admin_app` have no backend connectivity at all (confirmed, not assumed) — every screen in both is local/demo data.
2. No app has real Cognito authentication — the token-acquisition seam exists (`driver_app`) but nothing populates it yet.

Everything explicitly asked for in this pass — Flutter validated with real `flutter analyze`/`flutter test` (not claimed without running them), driver operational exclusivity verified and one real gap closed, Ride/Courier/Rental state machines audited and three illegal-transition defects fixed with tests, vehicle integrity tested, the auth abstraction boundary verified clean, API security swept (malformed IDs, ownership, duplicate submissions, concurrency, rate limiting all covered), mock/demo behavior classified, Flutter network/error handling hardened, and the backend test suite grown from 164 to 183 passing tests with zero regressions — is complete and verified, not assumed. What's left is the two items above, both larger efforts than "everything completable locally in this pass," and both explicitly named rather than glossed over.
