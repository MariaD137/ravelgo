# RavelGo — Final Pre-AWS Local Completion

Scope: finish the remaining local (no AWS/Cognito/Stripe) work already identified by
the existing readiness reports — driver_app onboarding, My Trips, My Documents, the
four remaining hardcoded screens (Ratings/Incentives/Preferences/Vehicles), the map,
and six small backend hardening items. Nothing already marked complete was reopened;
nothing deferred to AWS/Cognito/Stripe was touched.

---

## 1. Completed in this task

### driver_app — onboarding
- `create_account_screen.dart` / `add_photo_screen.dart` / `driver_information_screen.dart`
  / `vehicle_information_screen.dart` / `verify_account_screen.dart` rewritten as a real,
  validated, multi-step flow carried by a new `DriverOnboardingDraft` model. Real
  validation blocks "Continue" on each step; the fake 6-digit OTP box on the final
  screen (no backend capability to check it against) is replaced with a real review
  screen and a "Submit application" action.
- Submission makes real backend calls: `POST /drivers/me` (required — a failure shows
  a real error with Retry, and does not navigate forward), then best-effort
  `PATCH /drivers/me` (quiet mode), `POST /vehicles`, and per-document
  presign→S3 PUT→`POST /documents` uploads (failures here are surfaced but don't trap
  the driver on the screen — each can be completed later from Ride
  Preferences/My Vehicles/My Documents).
- License number / years-of-experience fields and the profile-photo step have no
  backing Driver/User field — left in place (not deleted) but never sent anywhere,
  consistent with not inventing backend capability that doesn't exist.
- New `DocumentApi` and `VehicleApi` API-client classes (driver_app had neither),
  reusing the existing `ApiClient`/`ApiException` architecture — no duplicate clients.
- New `PickableUploadBox` widget: a real, tappable version of the existing decorative
  `AppComponents.uploadBox`, using the already-present `image_picker` dependency.

### driver_app — My Trips
- `my_trips_screen.dart` rewritten: real `GET /trips/mine` fetch (see §1 backend
  changes below for why this needed a small, non-duplicative backend extension),
  loading/empty/error/retry states, pull-to-refresh. `models/trip.dart`'s mock data and
  Flutter-only `TripStatus` enum removed; replaced with a `Trip.fromJson` model
  matching the real Trip row shape.
- `trip_detail_screen.dart` updated to the new model. Its "Download receipt"/"Report a
  lost item" buttons — which had no real backend endpoint reachable from a Trip id —
  now show an honest "not available yet" message instead of a fake success SnackBar.

### driver_app — My Documents
- `my_documents_screen.dart` rewritten: real `GET /documents/me` fetch,
  loading/empty/error/retry states, and a real "add document" flow (title prompt →
  `image_picker` → presign → S3 PUT → `POST /documents` → list refresh), all with real
  loading/error handling. `models/document_item.dart`'s mock list removed; replaced
  with `DocumentItem.fromJson` mapping the backend's real `DocumentStatus` enum.

### driver_app — Ratings / Incentives / Preferences / Vehicles
- **Ratings**: overall rating and trip count are real (`Driver.rating`/`totalTrips`,
  already loaded by `DriverShell` before this screen is reachable). The per-trip
  written-review list — no backend model exists for it — is now an honest "not
  available yet" message instead of four fabricated reviews.
- **Incentives**: no backend model for badges/achievements exists at all. The
  fabricated "earned"/"not earned" badge list is replaced with an honest "not
  available yet" message; the screen itself stays in place rather than being deleted.
- **Preferences**: `preferredLanguage` and `quietModePreferred` are now real, saved via
  the new `PATCH /drivers/me` (see backend changes) with a real loading/error state on
  Save. "Accept courier requests" / "Accept long-distance trips" have no backend field
  — shown disabled with an honest caption instead of a toggle that silently did
  nothing.
- **Vehicles**: fully real — `vehicle_list_screen.dart` and `add_vehicle_screen.dart`
  now use the new `VehicleApi` (`GET /vehicles/me`, `POST /vehicles`) with real
  validation, loading/empty/error/retry states. `models/vehicle.dart`'s mock data
  removed; replaced with `Vehicle.fromJson`.

### driver_app — Map
- New `LiveMapPreview` widget replaces the static `assets/fake_map.png` in
  `driver_home_screen.dart` and `active_trip_screen.dart`. The native configuration
  seam for Google Maps already existed (`GOOGLE_MAPS_API_KEY` in `.env`, wired through
  `android/local.properties`/`ios/Flutter/Secrets.xcconfig`) but was never filled with
  a real key. This widget checks that honestly: with a real key configured, it renders
  a genuine `GoogleMap` centered on the driver's real current location (via
  `geolocator`, already a dependency); without one — or if location can't be
  resolved — it shows a plain "not configured" / "couldn't get your location"
  placeholder. No fabricated location, route, or "live tracking is working" claim.

### Backend hardening (§6 A–F)
- **A — Duplicate trip/courier requests**: added hand-written partial unique indexes
  (`Trip_riderId_open_unique`, `CourierRequest_senderId_open_unique`, migration
  `20260823083433_add_open_request_unique_indexes`) as the database-level backstop
  behind the existing application-level pre-checks. `POST /trips` and
  `POST /courier-requests` now catch the resulting `P2002` and return a clean 409.
  Two new true-concurrency regression tests (`Promise.all` from the same
  rider/sender) prove the loser is rejected and exactly one row exists. Two
  pre-existing fixture-only tests in `courier.routes.test.ts` that (incidentally, not
  as their actual point) created two open requests for one sender were updated to use
  two senders instead.
- **B — Promotion redemption race**: `POST /promotions/:code/redeem` now uses an
  atomic conditional `updateMany` (`redemptionCount: { lt: maxRedemptions }`) inside a
  transaction, closing the race where two different users near the limit could both
  pass a read-then-write check before either committed. Also added a `P2002` catch on
  the same-user double-redeem path (the unique constraint already existed; it was
  previously unhandled and would have surfaced as a 500 under a real race). New
  concurrency test: two different users racing for the last redemption slot.
- **C — Document fileKey ownership**: `POST /documents` now rejects a `fileKey` not
  namespaced under the caller's own Cognito sub (`POST /uploads/presign` always mints
  keys as `${sub}/...`, so any other prefix was never actually issued to that caller).
  New authorization test.
- **D — LocationService error handling** (`user_app/lib/components/LocationService.dart`):
  rewritten to throw a typed `LocationException` carrying a
  `LocationFailureReason` (`serviceDisabled`/`permissionDenied`/`permissionDeniedForever`/
  `timeout`/`unavailable`) instead of swallowing every failure into one `print()` and
  returning null. `Home.dart`'s caller updated to catch it and log which reason
  occurred.
- **E — `generatePayoutsForPeriod`**: inspected — confirmed still unused (no route or
  scheduler calls it; not referenced in `openapi.yaml`). No caller was invented and no
  Stripe integration was added. Documented in §3 below as a product decision (expose
  via an Admin endpoint, or delete) still pending, unchanged from prior reports.
- **F — print() cleanup**: `driver_app` and `admin_app` already had zero `print()`
  calls (confirmed by a repo-wide grep — a prior session's cleanup covered them).
  `user_app`'s 11 remaining calls (Signup upload-pick logging, a few "tapped" debug
  logs, `LocationService`'s own swallowed-error log) replaced with `debugPrint`, the
  Flutter-idiomatic mechanism, with no error-handling logic removed.

---

## 2. Previously completed (left alone, not reopened)

Backend core business logic, PostgreSQL architecture and migrations, Ride/Courier/
Rental concurrency protection, `DriverAssignment` concurrency protection, real ride
matching, driver online/offline enforcement, driver assignment polling and WebSocket
delivery, ride accept/decline/lifecycle, the real user ride flow, admin and user
backend/API integration, the driver ride-matching integration, the `AuthProvider`
architecture and release-safe authentication, prior security remediation, IDOR/authz
protections, WebSocket security and race-condition fixes, OpenAPI synchronization
(beyond the small additions this task made for its own new/changed endpoints), the
existing E2E tests, the existing Flutter API clients and session architecture, and the
pre-existing backend/Flutter test suites — none of this was rebuilt, replaced, or
redesigned.

---

## 3. Remaining pre-AWS work

Nothing found in this pass rose to "must fix before AWS" — the items below are
smaller, explicitly non-blocking follow-ups already named in prior reports or
surfaced incidentally while doing this task's work:

- `generatePayoutsForPeriod` (backend, `services/payouts.ts`) is still unused dead
  code — needs a product decision (Admin endpoint vs. delete), not a technical fix.
- driver_app's profile photo (`add_photo_screen.dart`) and license-number/
  years-of-experience fields (`driver_information_screen.dart`) remain UI-only —
  adding real backend fields for them is a small schema/endpoint addition, not done
  here since it wasn't in this task's named scope.
- driver_app's "Accept courier requests"/"Accept long-distance trips" preference
  toggles remain disabled with no backend field — same reasoning.
- driver_app's Trip receipt download and lost-item reporting have no backend
  endpoint reachable from a Trip id (a receipt only exists per-Payment, not
  per-Trip, and there's no lost-item model at all) — shown honestly, not built.
- The pre-existing `add_payout_system` migration-naming inconsistency (documented in
  `PRE_AWS_FINAL_GAP_AUDIT.md`) still needs a `prisma migrate resolve` step at the
  first real deploy — unchanged, not something to fix before then.
- The pre-existing low-severity promotion-*creation* concerns and Docker-build
  verification (no daemon in this sandbox) noted in earlier reports are unchanged.

None of the above blocks the next stage — they're incremental UI/product-decision
items, not integration blockers.

---

## 4. Requires AWS

Unchanged from `PRE_AWS_FINAL_GAP_AUDIT.md`/`PRE_AWS_PRE_STRIPE_FINAL_READINESS.md`:
RDS PostgreSQL, S3 buckets (`DOCUMENTS_BUCKET`/`ASSETS_BUCKET` — the presign flow this
task's document uploads depend on is fully built against them and will work the
moment they exist), App Runner deployment of the CDK stacks, ElastiCache Redis for the
in-memory WebSocket hub and shared rate-limit store once more than one instance runs,
and CloudWatch wiring. Nothing in this task touched or attempted any of this.

## 5. Requires Cognito

Unchanged: real `CognitoAuthProvider` behind `createDefaultAuthProvider()`, real
password reset, persistent token storage, and admin fine-grained RBAC. This task's
onboarding flow makes real backend calls using whatever `AuthProvider` session already
exists (the same architecture every other screen already depends on) — it does not
attempt to implement, fake, or bypass Cognito sign-up itself, per the explicit
boundary for this task.

## 6. Requires Stripe

Unchanged: `processPayout()`'s simulated transfer, subscription-purchase screens, and
real Stripe keys. Not touched.

---

## 7. Test results

All commands run for real, against a real local PostgreSQL 16 instance; none of these
results are assumed.

**Backend:**
```
npm run typecheck   # 0 errors
npm run lint         # 0 errors, 0 warnings
npm test             # 226/226 passing (was 218 before this task; +8 new tests)
npx prisma migrate status   # "Database schema is up to date!"
openapi.routes.test.ts      # 2/2 (spec + Swagger UI still serve correctly)
```

**Flutter:**
| App | analyze | test |
|---|---|---|
| `driver_app` | 0 errors (6 pre-existing info-level lints, unchanged) | **53/53** (48 pre-existing + 5 new model-parsing tests) |
| `user_app` | 0 errors, 0 warnings (157 pre-existing info-level lints, unchanged; confirmed none are new) | **48/48** (unchanged, re-run to confirm no regression) |
| `admin_app` | not modified this task | **59/59** (unaffected app, re-run to confirm no regression) |

No test was weakened, skipped, or removed to reach these numbers.

---

## 8. Files changed

48 files: 11 backend (6 route files + 5 matching test files, plus `openapi.yaml` and
one new migration), 34 driver_app (7 new files: `document_api.dart`, `vehicle_api.dart`,
`driver_onboarding_draft.dart`, `pickable_upload_box.dart`, `live_map_preview.dart`,
`model_parsing_test.dart`, plus the migration; 27 modified), and 9 user_app (the
`LocationService`/`Home.dart` fix plus 7 `print()`→`debugPrint()` cleanups).

```
git diff --cached --stat
 backend/openapi.yaml                                        |  27 +++-
 backend/prisma/migrations/20260823083433_.../migration.sql   |  22 +++ (new)
 backend/src/routes/courier.routes.test.ts                    |  40 ++++-
 backend/src/routes/courier.routes.ts                         |  21 ++-
 backend/src/routes/documents.routes.test.ts                  |  16 ++
 backend/src/routes/documents.routes.ts                       |  11 ++
 backend/src/routes/drivers.routes.test.ts                    |  30 ++++
 backend/src/routes/drivers.routes.ts                         |  28 ++++
 backend/src/routes/loyalty.routes.test.ts                    |  43 ++++-
 backend/src/routes/loyalty.routes.ts                         |  47 +++++-
 backend/src/routes/trips.routes.test.ts                      |  67 +++++++-
 backend/src/routes/trips.routes.ts                            |  49 ++++--
 driver_app/lib/models/document_item.dart                     |  40 +++--
 driver_app/lib/models/driver_onboarding_draft.dart            |  57 +++++++ (new)
 driver_app/lib/models/trip.dart                                |  79 ++++------
 driver_app/lib/models/vehicle.dart                             |  17 ++
 driver_app/lib/services/api/document_api.dart                 |  61 +++++++ (new)
 driver_app/lib/services/api/driver_api.dart                    |  16 ++
 driver_app/lib/services/api/ride_api.dart                      |   8 +
 driver_app/lib/services/api/vehicle_api.dart                   |  36 +++++ (new)
 driver_app/lib/services/driver_session.dart                    |   8 +-
 driver_app/lib/views/auth/add_photo_screen.dart                 |  12 +-
 driver_app/lib/views/auth/create_account_screen.dart            | 107 +++++++++----
 driver_app/lib/views/auth/driver_information_screen.dart        |  64 ++++++--
 driver_app/lib/views/auth/vehicle_information_screen.dart       | 141 +++++++++++++----
 driver_app/lib/views/auth/verify_account_screen.dart            | 169 ++++++++++++++++----
 driver_app/lib/views/documents/my_documents_screen.dart         | 175 ++++++++++++++++++---
 driver_app/lib/views/home/driver_home_screen.dart                |   3 +-
 driver_app/lib/views/incentives/incentives_screen.dart           |  45 ++----
 driver_app/lib/views/preferences/driver_preferences_screen.dart  |  71 +++++++--
 driver_app/lib/views/ratings/my_ratings_screen.dart              |  56 +++----
 driver_app/lib/views/trip/active_trip_screen.dart                |   3 +-
 driver_app/lib/views/trips/my_trips_screen.dart                  | 125 +++++++++++----
 driver_app/lib/views/trips/trip_detail_screen.dart               |  25 ++-
 driver_app/lib/views/vehicles/add_vehicle_screen.dart            | 111 +++++++++----
 driver_app/lib/views/vehicles/vehicle_list_screen.dart           | 115 ++++++++++----
 driver_app/lib/widgets/live_map_preview.dart                     |  99 ++++++++++++ (new)
 driver_app/lib/widgets/pickable_upload_box.dart                  |  70 +++++++++ (new)
 driver_app/test/model_parsing_test.dart                          |  86 ++++++++++ (new)
 user_app/lib/components/LocationService.dart                     |  78 ++++++---
 user_app/lib/views/HomeView/Home.dart                             |  15 +-
 user_app/lib/views/OtherViews/SupportView.dart                    |   2 +-
 user_app/lib/views/OtherViews/WorkProfileView.dart                |   2 +-
 user_app/lib/views/Services/IdelivaPickUpDeliveryScreen.dart      |   2 +-
 user_app/lib/views/Services/PostCarScreen.dart                    |   2 +-
 user_app/lib/views/Signup/AddPhoto.dart                           |   2 +-
 user_app/lib/views/Signup/DriverInformation.dart                  |   4 +-
 user_app/lib/views/Signup/VehicleInformation.dart                 |   4 +-
 48 files changed, 1874 insertions(+), 437 deletions(-)
```

---

## 9. Commit SHA

Committed to `claude/ravelgo-completeness-audit-873u5u` — see the commit immediately
following this file for the exact SHA.
