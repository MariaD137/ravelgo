# RavelGo — Post-Mock Integration Readiness

Follow-up to `PRE_AWS_FINAL_GAP_AUDIT.md` (commit `6f62d3b`). That audit intentionally left two
large implementation gaps unfinished: **admin_app** UI still relying on hardcoded/mock data despite
real backend APIs already existing, and **user_app**'s ride-request flow still relying on
hardcoded/mock data. This report covers finishing both, proving the full chain (Flutter UI → API
client → HTTP → backend → authorization → Prisma → PostgreSQL → response → Flutter state) for every
action fixed, and a repo-wide sweep for everything else still mocked.

## 1. Executive verdict

**NOT READY — BLOCKERS REMAIN**

admin_app (Part 1) and user_app's ride-request flow (Part 2) — the two gaps this task was scoped to
close — are both done and verified end-to-end against the real local backend. The repo-wide sweep
required by Part 10, however, found substantial mock/simulated behavior **outside** that scope,
most seriously: **driver_app's entire ride-matching flow is an explicit local simulation**, never
wired to the real, already-working matching engine a driver would actually need. A rider using the
now-real user_app flow and a driver using driver_app's still-simulated flow would never actually
meet. That is a blocker to calling the system ready for AWS/Cognito/Stripe integration, independent
of anything Cognito/AWS/Stripe-specific. Full detail in Section 7.

## 2. Admin app — feature table

| Feature | Previously Mocked? | Real API? | Tested? | Status |
|---|---|---|---|---|
| Dashboard KPIs | Yes | Yes (`GET /api/admin/*` KPI endpoints, pre-existing) | Yes — `dashboard_api_test.dart` | Done |
| Driver list & detail (suspend/reactivate, document approve) | Yes | Yes (`GET/PATCH /api/drivers`) | Yes — `driver_api_test.dart` + `admin-driver-lifecycle.e2e.test.ts` (real Postgres) | Done |
| Rider list & detail (suspend/reactivate) | Yes | Yes (`GET/PATCH /api/riders`) | Yes — `rider_api_test.dart` + same e2e file | Done |
| Trip monitoring ("flag for review") | Yes | Yes (`GET/PATCH /api/trips`) | Yes — `trip_api_test.dart` | Done |
| Courier requests | Yes | Yes (`GET /api/courier-requests`) | Yes — `courier_api_test.dart` | Done |
| Rental listings (approve/reject) | Yes | Yes (`GET/PATCH /api/rental-listings`) | Yes — `rental_api_test.dart` | Done |
| Car Paddy requests (approve/reject) | Yes | Yes (`GET/PATCH /api/car-paddy`) | Yes — `carpaddy_api_test.dart` + backend `carpaddy.routes.test.ts` (new state-machine guard) | Done |
| Support tickets | Yes | Yes (`GET/PATCH /api/support-tickets`) | Yes — `support_api_test.dart` | Done |
| Safety alerts (SOS + fraud, acknowledge/resolve) | Yes | Yes (`GET/PATCH /api/emergency-alerts`) | Yes — `alerts_api_test.dart` | Done |
| Pricing rules & surge zones | Yes | Yes (`GET/POST/PATCH /api/pricing-rules`, `/api/surge-zones`) | Yes — `pricing_api_test.dart` | Done |
| Driver subscriptions (read-only) | Yes | Yes (`GET /api/subscription-plans`) | Yes — `subscription_api_test.dart` | Done |
| Loyalty tiers & promotions (create promo) | Yes | Yes (`GET /api/loyalty-tiers`, `GET/POST /api/promotions`) | Yes — `loyalty_api_test.dart` | Done |
| Weekly analytics (trips + revenue) | Yes (fake per-day bar charts, fake "driver online hours") | Yes — **new** `GET /api/admin/reports/weekly` | Yes — `admin_api_test.dart` + `admin.routes.test.ts` | Done |
| Admin's own profile | Yes | Yes — **new** `GET/POST /api/admin/me` | Yes — `admin_api_test.dart` + `admin.routes.test.ts` | Done |
| Fine-grained admin roles (Super Admin / Ops / Support / Finance) | Yes (invented staff list) | No — no backend model exists | N/A | Replaced with an honest "not available yet — needs Cognito custom groups" screen, not fabricated data |

Every mutation above (suspend, approve, reject, acknowledge, resolve, decide) was traced through to
a real Prisma write and independently re-read from Postgres in `admin-driver-lifecycle.e2e.test.ts`,
not assumed from the HTTP response alone.

## 3. User app (ride flow + account) — feature table

| Feature | Real API? | Backend Verified? | E2E Tested? | Status |
|---|---|---|---|---|
| Pickup selection (Places search + real device GPS via `geolocator`) | Yes (Google Places, existing) | N/A (client-side) | Manual code review (no physical device in this environment) | Done |
| Destination selection + real distance/duration (haversine from actual coordinates) | N/A (local computation) | N/A | Yes — `ride_session_test.dart` | Done |
| Fare quote | Yes (`GET /api/pricing/quote`) | Yes | Yes — `ride_session_test.dart` + `ride-lifecycle.e2e.test.ts` | Done |
| Ride request | Yes (`POST /api/trips`) | Yes | Yes — `ride-lifecycle.e2e.test.ts` (real fare computed server-side, real auto-match, duplicate-request 409 proven) | Done |
| Live trip status (polling) | Yes (`GET /api/trips/:id`, 4s interval) | Yes | Yes — driven through `RideSession` | Done |
| Live trip status (WebSocket) | Yes — real `wss://…/ws` connect + subscribe, best-effort overlay on polling | Backend WS infra pre-existing (`docs/realtime-architecture.md`) | **No** — needs a real Cognito access token this sandbox cannot issue; polling is the proven primary path per design | Wired, not live-auth-tested |
| Cancel ride | Yes (`PATCH /api/trips/:id/cancel`) | Yes | Yes — `ride-lifecycle.e2e.test.ts` (409 on an already-terminal trip proven) | Done |
| Trip completion / receipt | Yes (`PATCH /api/trips/:id/status`, `finalFare`) | Yes | Yes — `ride-lifecycle.e2e.test.ts` | Done |
| Trip history | Yes (`GET /api/trips/mine`) | Yes | Yes — `ride-lifecycle.e2e.test.ts` | Done |
| Account profile (view) | Yes (`GET /api/riders/me`) | Yes | Yes — `rider_api_test.dart` + `riders.routes.test.ts` | Done |
| Account profile (edit name/phone) | Yes — **new** `PATCH /api/riders/me` | Yes | Yes — `rider_api_test.dart` + `riders.routes.test.ts` | Done |
| Side drawer (real name, working navigation) | Yes | Yes | Manual + `flutter analyze`/`flutter test` | Done |
| Scheduled ("book ahead") rides | No backend capability (no scheduling model exists) | N/A | N/A | Replaced with an honest "not available yet" screen, not fabricated bookings |
| "Ravel driver portal" (a second, fake driver app embedded inside user_app) | No | No | No | **Not fixed this pass** — duplicates driver_app; see Section 7 |
| "Services" (car-rental marketplace + i-deliva, ~20 screens) | No | No | No | **Not fixed this pass** — no backend for this domain exists; see Section 7 |
| Subscription purchase | No (fake "Congratulations" message, no charge) | No | No | **Not fixed this pass** — needs Stripe; see Section 9 |
| Delete account | No (button is a no-op) | No | No | **Not fixed this pass** — needs a new endpoint + a soft- vs hard-delete decision (Trip/Payment FKs); see Section 7 |

## 4. Mock data removed this pass

**admin_app** — every screen's hardcoded list/detail data (drivers, riders, trips, couriers,
rentals, car-paddy requests, support tickets, alerts, pricing rules, subscriptions, loyalty
tiers/promotions), a fabricated surge-multiplier slider and traffic-discount toggle with no backend
field, fake per-day analytics bar charts, a fabricated "driver online hours" metric, an invented
admin-roles staff list, a `TextField(hintText:)`-only profile field that never actually rendered
its value.

**user_app** —
- `FindRoute.dart`'s pickup/destination flow (previously navigated on any tap without capturing real
  coordinates or feeding them anywhere)
- `SelectRide.dart`'s three hardcoded ride-type cards with fixed fares ("Just ride #8000", "EV
  #6000", "Lite #5000") — collapsed to one real quoted fare, since the backend has no
  category-based pricing to fake a second/third price against
- `FindDriverScreen.dart`'s fake 10-car map marker generator and hardcoded trip/fare text
- `SearchDriverScreen.dart`'s fake "5 drivers are viewing your request" banner, fake offer/auto-accept
  toggle, and the `RequestDriverScreen.dart` 3-driver Accept/Decline list (deleted outright — the
  backend performs exactly one atomic match, there is no rider-side driver selection to fake)
- `ride_view_popup.dart`'s internal `Timer.periodic` that advanced a fake "stage" 1→4 every 30
  seconds regardless of any real trip state, hardcoded driver "Thelma Ibeh"/"4.55 Rating"
- `RidesView.dart`/`RideDetailsView.dart`'s fully hardcoded trip history ("Denco court 1", fixed
  dates, `#2444`) and receipt (fake "24 kusenla road"/"Dutse"/"Madiba" stops, fake VAT line)
- `Account.dart`/`PersonalInfo.dart`/`EditProfileInfo.dart`'s hardcoded name/phone/email and a fake
  plaintext **password field** ("John50c") with no backend equivalent at all — removed, not replaced
- `user_summary.dart`'s hardcoded "4.55 Rating" and two "Acceptance rate" cards that never showed a
  number — riders have no rating/acceptance-rate concept in this schema; replaced with a real trip
  count
- `SideMenu.dart`'s hardcoded "Thelma"/"Ibeh" and five drawer items that did nothing on tap
- `scheduled_rides_screen.dart`'s inverted-logic fake request list (`hasRequests`/`hasConfirm` were
  always `false`, so the "empty" branch could never actually render) and its `RideController`
  singleton, which simulated an active ride locally with no real trip behind it — replaced with an
  honest empty state; `RideController` itself is now deleted (superseded by `RideSession`, which is
  driven by real backend state)

## 5. Backend changes made this pass

- `POST /api/admin/me`, `GET /api/admin/me` — admin's own profile bootstrap (mirrors the pre-existing
  `/riders/me`, `/drivers/me` pattern)
- `GET /api/admin/reports/weekly` — real trips-completed + revenue aggregate over the last 7 days
- `PATCH /api/riders/me` — update the rider's own name/phone (not email, which stays tied to the
  Cognito identity); uses the repo's established conditional-`updateMany` pattern rather than a plain
  `.update()` that would throw on a never-bootstrapped profile
- `PATCH /api/car-paddy/:id` — fixed a genuine pre-existing gap: this endpoint had no previous-state
  guard at all (an unconditional `.update()`), unlike every sibling state-machine route in this repo;
  now enforces `SUBMITTED`/`IN_REVIEW` → decided, with a 409 on an illegal transition
- `openapi.yaml` — documented all of the above
- `backend/src/e2e/` — two new end-to-end test files (Section 6) exercising the real Express app +
  real Prisma client against the real local Postgres instance

## 6. Test results (exact)

Run against a live local Postgres instance (`postgresql://ravelgo:ravelgo@localhost:5432/ravelgo`),
`node --test --test-concurrency=1`, `npm run typecheck` (`tsc --noEmit`), `npm run lint` (ESLint),
and `flutter analyze` / `flutter test` for all three Flutter apps, all run in this session:

| Check | Result |
|---|---|
| Backend `npm test` (unit + integration + the 2 new e2e files, real Postgres) | **209 / 209 passed**, 0 failed |
| Backend `npm run typecheck` | Clean, 0 errors |
| Backend `npm run lint` (ESLint) | Clean, 0 errors/warnings |
| `npx prisma migrate status` | 6 migrations found, database schema up to date — no new migration needed this pass |
| `openapi.yaml` | Parses as valid YAML, 73 documented paths |
| `admin_app` — `flutter analyze` | 0 errors, 0 warnings |
| `admin_app` — `flutter test` | **59 / 59 passed** |
| `user_app` — `flutter analyze` | 0 errors, 0 warnings |
| `user_app` — `flutter test` | **48 / 48 passed** |
| `driver_app` — `flutter analyze` | 0 errors, 0 warnings |
| `driver_app` — `flutter test` | **38 / 38 passed** |

**E2E scenarios proven** (both inside the 209 backend-test count, exercised via `supertest` against
the real Express `app` + real Prisma client + real Postgres — only Cognito JWT *signature
verification* is stubbed, the same mechanism the repo's existing 200+ tests already use, since no
real Cognito user pool exists locally):

- **Admin**: bootstrap a real driver → admin lists drivers → admin activates → admin suspends →
  independent Postgres re-read confirms `SUSPENDED` persisted → admin unsuspends → independent
  re-read confirms `ACTIVE` persisted; a non-Admin caller attempting the same PATCH gets a real 403;
  a second administrative mutation (rider suspend) is proven to actually block the suspended rider's
  next request via `requireAuth`'s own suspension check, not just return `200`.
- **User ride lifecycle**: real driver + real rider bootstrapped → rider requests a trip with real
  distance/duration → backend computes the fare server-side (asserted equal to the exact formula,
  proving the client's `estimatedFare` is never trusted) → the one ACTIVE unencumbered driver is
  auto-matched → a duplicate request from the same rider is rejected with 409 → driver advances
  `IN_PROGRESS` → driver completes with a real `finalFare` inside the allowed band → independent
  Postgres re-read confirms the completed trip and `finalFare` persisted → the driver's
  `DriverAssignment` is confirmed released (matchable again) → the rider's `GET /trips/mine` shows
  the real completed trip with the real driver's name attached. A second scenario proves
  pre-match cancellation and the 409 on cancelling an already-cancelled trip.

**Not tested this pass**: a live, real-Cognito-authenticated WebSocket round-trip. The local
`COGNITO_USER_POOL_ID`/`COGNITO_CLIENT_ID` are placeholders (`us-east-1_XXXXXXXXX`), so the live dev
server's `CognitoJwtVerifier` cannot verify any token this sandbox can produce — this is a Cognito
blocker, not a code defect (see Section 7). `RideSession`'s WebSocket wiring itself (connect,
subscribe message, message parsing, and the requirement that a connect/ready failure never break
polling) is unit-tested with a `MockClient`; a genuine `WebSocketChannelException` from an
unreachable/refused connection was reproduced and fixed during this session — `WebSocketChannel`
surfaces a bad connection as a rejected `ready` future, not through the message stream, and the
original code wasn't awaiting it, which would have been an unhandled async error in production.

## 7. Remaining blockers

**Local/code blockers** (fixable without any external service, not yet done — found by the Part 10
repo-wide sweep, outside this task's Part 1/Part 2 scope):

- **driver_app's entire ride-matching flow is an explicit local simulation.** `driver_home_screen.dart`
  has a hardcoded `_demoRequest` and a button literally labeled "Simulate incoming ride request";
  `active_trip_screen.dart`'s own comment states *"This ride flow is still a local simulation... not
  a real backend Trip."* The backend matching engine this session verified end-to-end
  (`services/matching.ts`) is real and working — driver_app's UI simply never calls it. This is the
  single most significant remaining gap: a real rider (now fully wired) has no real driver to be
  matched with in practice.
- driver_app's own profile is hardcoded ("Thelma Ibeh" everywhere) despite a real, working
  `GET /api/drivers/me` that is simply never called from `DriverShell`.
- driver_app's map is a static `fake_map.png` image everywhere, despite `google_maps_flutter` being
  a declared, unused dependency.
- driver_app's onboarding (create account → driver/vehicle info → verify) collects form input that
  is never submitted anywhere; My Trips/My Documents/Ratings/Incentives/Preferences/Vehicles all
  render hardcoded arrays despite several corresponding backend endpoints already existing.
- user_app's "Ravel driver portal" section (reachable from the now-real Account screen) is an
  entirely separate, 100% fake duplicate of driver_app's functionality — zero API calls anywhere
  across 8 files.
- user_app's "Services" tab (car-rental marketplace + i-deliva onboarding, ~20 files) has no backend
  support built for it at all — this is unbuilt feature work, not a wiring gap.
- user_app's "Delete account" button is a no-op; no backend delete-account endpoint exists.
  Building one is nontrivial: `Trip.riderId`/`Payment.userId` etc. have no cascade-delete behavior
  defined, so a hard delete would need those addressed first, or a soft-delete field added via
  migration — a real product/data decision, not a one-line fix.

**Cognito blocker**: `COGNITO_USER_POOL_ID`/`COGNITO_CLIENT_ID` are placeholder values; there is no
real Cognito User Pool. This blocks: real device sign-in in any of the 3 apps (all currently run on
`DevOnlyAuthProvider`/`UnauthenticatedAuthProvider`), a live-authenticated WebSocket E2E proof, and
fine-grained admin RBAC (the natural implementation is Cognito custom groups, per
`admin_roles_screen.dart`'s own honest-empty-state explanation).

**AWS blocker**: no RDS/App Runner/S3/CloudFront/CloudWatch exist — intentionally, per this task's
explicit instructions. Everything above was validated against local Postgres and a local dev server
only.

**Stripe blocker**: `backend/src/services/payouts.ts`'s `processPayout` still fabricates a successful
transfer (`transactionId: `stripe_payout_${Date.now()}``) behind a real, admin-facing
`POST /api/payouts/:id/process` route — an admin clicking "process payout" today gets a fake
transaction ID with no real money movement. Both driver_app's and user_app's subscription "purchase"
screens show a hardcoded success message without charging anything. No Stripe keys are configured,
per this task's explicit instructions.

## 8. AWS readiness (not deploying — readiness for the next phase)

The backend itself is close to App Runner-ready from prior sessions' work: `trust proxy` is
configured for App Runner's load balancer, migrations are tracked and applied cleanly
(`prisma migrate status` clean against local Postgres), `/health` reports real DB connectivity,
graceful shutdown is wired, security headers and rate limiting are in place, and CORS/env config are
documented in `.env.example`. Nothing in this pass touched infrastructure config. The concrete next
steps once AWS access exists: provision RDS Postgres and re-run `prisma migrate deploy` against it
(no new migration was needed this pass); provision the real Cognito User Pool this whole codebase's
`AuthProvider` abstraction is already built to receive with no route/API-client changes; wire the 3
Flutter apps' `createDefaultAuthProvider()` to a real Cognito-backed implementation of the existing
`AuthProvider` interface. None of that is started — this section describes readiness, not doneness.

## 9. Stripe readiness (not integrating — what remains Stripe-dependent)

Three concrete integration points, none touched this pass: (1) `services/payouts.ts`'s
`processPayout` needs a real Stripe Connect transfer call in place of the simulated one; (2)
driver_app's and user_app's subscription-purchase screens need a real payment flow (Payment Intent
creation, confirmation, and only-then marking the `DriverSubscription`/plan active) in place of the
unconditional "success" navigation; (3) the yet-to-be-built car-rental "Services" flow would need
payment/booking-deposit handling if it's ever built out. The backend's `billing/stripe.ts` already
exists and is exercised only via test-mocked calls (`mockPaymentIntentCreate`) — no real Stripe keys
are configured, per this task's explicit instructions.

## 10. Final recommendation

The next logical engineering step is **not** Cognito/AWS/Stripe integration yet — it's closing the
driver_app gap this report's sweep surfaced (Section 7's first item), since it is the one remaining
issue that makes the just-completed rider-side work non-functional end-to-end in practice: wire
`driver_home_screen.dart`/`active_trip_screen.dart` to the real, already-verified matching/trip
endpoints, the same way this session wired user_app, following the identical `DriverSession`/real-API
pattern already proven twice in this codebase (courier flow, and now ride flow). Once that's done,
every core operational flow across all three apps runs on real data end-to-end, and the codebase is
positioned to move to Cognito integration next (the `AuthProvider` abstraction is already uniform and
ready to receive it across all 3 apps), then AWS infrastructure, then Stripe.

---

**Final commit**: `c599d5e4506c659a5eaa767c6302751d980e208c` (branch
`claude/ravelgo-completeness-audit-873u5u`, pushed to `origin`)

**Files changed this pass**: 75 across 2 commits — `4663ed8` (69 files: admin_app screens/models/API
clients, user_app ride-flow screens/services/tests, backend routes/tests/openapi/e2e) and `c599d5e`
(6 files: admin_app API client unit tests)
