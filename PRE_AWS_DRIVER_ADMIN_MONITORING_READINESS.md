# Driver Dashboard + Admin Fleet Monitoring — Readiness Report

Scope: fix the driver-dashboard and admin-driver-monitoring gaps identified
against `docs/PRD.md` (see §9.1). Local/pre-AWS only — no AWS, Cognito, or
Stripe resources were created or touched.

## 1. What was already complete (found by inspection, reused as-is)

- Driver approval state machine (`Driver.status`: `PENDING_REVIEW` →
  `ACTIVE` → `SUSPENDED`), and `PATCH /api/drivers/:id/status` for
  admin suspend/reactivate — unchanged, only extended to also force
  presence offline and broadcast a fleet event on suspend.
- Cognito JWT auth + role middleware (`requireAuth`, `requireRole`) —
  reused unchanged for every new route.
- The single-container `ws` real-time hub and per-trip rooms
  (`src/realtime/hub.ts`, `src/realtime/server.ts`) — reused and extended
  with a second, separate room rather than replaced.
- `GET /api/drivers`, `GET /api/drivers/:id`, `GET /api/drivers/me` —
  unchanged.
- Payout commission calculation (`calculatePayoutForPeriod`) — reused; its
  20% rate is now a named export (`PLATFORM_FEE_PERCENT`) so the driver
  summary endpoint uses the exact same rate instead of a second hardcoded
  copy.
- `admin_app`'s driver list/detail screens (approve, suspend, document
  review) — **not touched**; they were already correctly wired to
  `GET /drivers`/`PATCH /drivers/:id/status` conceptually but are still on
  mock data (`mockDrivers`). That's the same "connect the app to the real
  backend" launch blocker already tracked in `docs/PRD.md` §9/§10 — out of
  scope for this pass, which targeted presence/dashboard specifically.

## 2. Important correction to the task's own premises

The task brief describing this work referenced a `DriverOffer`/`TripOffer`
system, a `DriverAssignment` system, `DriverApi`/`DriverSession`/
`AuthProvider` architecture, and an existing Cognito seam in the Flutter
apps as already implemented. Direct inspection of `backend/prisma/schema.prisma`
(no `TripOffer`/`DriverOffer`/`DriverAssignment` models exist — ride
matching is a synchronous "first available driver" assignment in
`backend/src/services/matching.ts`) and of all three Flutter apps (no
networking, HTTP client, or auth session code existed anywhere before this
change) shows none of that existed in this repository. Per the instruction
not to fabricate or invent duplicate systems, **Part 9 (acceptance rate)
was not implemented** — there is no offer lifecycle to compute it from, and
building one is materially larger scope than presence/dashboard work. This
is recorded here rather than silently skipped.

## 3. Driver presence — implemented and verified

- `Driver.isOnline` (boolean) and `Driver.lastOnlineAt` persisted on the
  driver row; `DriverOnlineSession` (new model) logs each online→offline
  span, with a partial unique index (`DriverOnlineSession_one_open_per_driver`)
  guaranteeing at most one open session per driver at the database level.
- `PATCH /api/drivers/me/online` (`backend/src/routes/drivers.routes.ts`)
  is the authoritative toggle, backed by `backend/src/services/presence.ts`:
  - `ACTIVE` → can go online or offline.
  - `PENDING_REVIEW` → 403 with an honest reason ("still pending review").
  - `SUSPENDED` → 403 going online, but can always go offline.
  - Idempotent: repeated "online" calls do not open a second session
    (checked against the driver's current `isOnline`, and backstopped by
    the DB partial unique index for concurrent requests).
  - `PATCH /api/drivers/:id/status` (admin suspend) now also force-closes
    an open session and flips `isOnline` false, so a suspended driver is
    never left showing "online".
- Online hours are computed from `DriverOnlineSession` rows for the current
  calendar day (`getOnlineHoursToday`), including a still-open session up
  to "now" — never a client-side timer.

## 4. Driver dashboard — implemented and verified

- `GET /api/drivers/me/summary` (new): today's completed-trip count, gross
  fare, platform fee, net earnings (gross − platform fee, using the shared
  `PLATFORM_FEE_PERCENT`), online hours today, current rating, and total
  trips — all computed from real `Trip`/`Payment`/`DriverOnlineSession`
  rows for the authenticated driver only. No `id` parameter exists on this
  route; it is impossible to request another driver's summary by changing
  an id.
- `driver_app`'s home screen (`lib/views/home/driver_home_screen.dart`) now
  fetches this on load and pull-to-refresh, replacing the hardcoded
  "₦18,400 / 6 trips / 5h 20m". States implemented: loading ("Loading your
  dashboard..."), error ("Unable to load dashboard" + the backend's own
  reason + "Try again" retry button), and an inline "No activity yet" note
  when trips and online hours are both zero (kept as an inline note rather
  than replacing the whole screen, since the online toggle must stay
  usable even with no activity yet).
- The online/offline switch now calls `PATCH /api/drivers/me/online`
  (via `lib/services/driver_api.dart`) and only updates the UI after the
  backend confirms — a rejected toggle shows the backend's real reason in
  a SnackBar instead of silently flipping the switch.

## 5. Admin fleet monitoring — implemented and verified

- `GET /api/admin/dashboard`'s `onlineDrivers` field was counting
  `Driver.status = ACTIVE` (verification/approval), which is not presence
  — an approved, offline driver was counted as "online". Fixed to count
  `isOnline: true`. Covered by an updated test that creates one ACTIVE
  driver online and one ACTIVE driver offline to prove the fix
  distinguishes them (the old test would have passed either way).
- `GET /api/admin/drivers/presence` (new): fleet counts (total, online,
  offline, active, pending review, suspended) plus a per-driver list
  (identity, status, presence, online-since, current trip if
  matched/in-progress, primary vehicle, last known location). Location is
  either a real `{lat,lng,updatedAt}` from the existing per-trip WS hub or
  the literal string `"Location unavailable"` — never fabricated
  coordinates, and covered by a test asserting exactly that string when no
  location has been reported.
- `admin_app`'s dashboard now fetches both endpoints on load (loading /
  error+retry / empty states implemented) and renders an "Online now (N)"
  section listing currently-online drivers with vehicle + location label.
  The "Rides this week" chart and "Recent trips" list are left as the
  pre-existing mock data — there is no backend endpoint for historical
  revenue/ride-volume reporting, and building one is out of scope for this
  presence/monitoring fix (noted in code and in `docs/PRD.md` §9.1).

## 6. Real-time admin channel

A new Admin-only `subscribe:fleet` WebSocket room (`joinFleetRoom` /
`broadcastFleetEvent` in `src/realtime/hub.ts`) delivers `driver:online`,
`driver:offline`, `driver:suspended`, `driver:trip_started`, and
`driver:trip_completed` events, fired from the online-toggle, suspend, and
trip-status routes respectively. This reuses the existing single-container
`ws` server (no new infrastructure, no AWS) — same in-memory, single-
instance caveat as the rest of the hub (documented in
`docs/realtime-architecture.md`, unchanged). A Driver or Rider socket
requesting `subscribe:fleet` gets a plain `{"type":"error"}`, never a
partial grant — covered by a test. `GET /api/admin/drivers/presence` is the
REST/polling equivalent for a client that isn't WS-connected, satisfying
the "don't fake real-time, provide honest polling + a clean seam" guidance
for anything that would otherwise need AWS infrastructure that doesn't
exist yet — it doesn't, here, so both were implemented.

## 7. Acceptance-rate (Part 9)

Not implemented. See §2 above — there is no offer/decline system in this
codebase to compute it from, and inventing one would itself be "duplicating
a system" in the wrong direction (creating a new one where the brief
assumed one already existed). Recorded as a real scope gap, not a fake
blocker: if driver acceptance-rate reporting is wanted, it should be scoped
against an actual multi-offer dispatch design.

## 8. Security / authorization verification

Verified by test (see §11) and by construction (no route accepts a driver
id for self-scoped actions):

- A driver can only ever read/toggle their own summary/presence
  (`/drivers/me/*`, scoped by Cognito `sub` → `Driver`, no id parameter
  exists to change).
- `PENDING_REVIEW` and `SUSPENDED` drivers cannot go online (403 with a
  real reason); `SUSPENDED` can always go offline.
- `/admin/drivers/presence` and `/admin/dashboard` require `requireRole("Admin")`
  — a Driver or Rider caller gets 403.
- `subscribe:fleet` requires the Admin Cognito group on the WS connection
  — a Driver socket gets an error, not a partial join.
- No existing authorization was weakened; all new routes reuse
  `requireAuth`/`requireRole` unchanged.

## 9. Tests and results (all actually run in this session)

**Backend** — local Postgres 16, migrations applied from a clean
`DROP DATABASE`/`CREATE DATABASE` to confirm the new migration applies
cleanly on top of all four existing ones:

```
$ npx prisma migrate deploy         → 5/5 migrations applied cleanly
$ NODE_ENV=test npm test            → 100 tests, 100 pass, 0 fail
$ npx tsc --noEmit                  → clean, no errors
$ npm run lint                      → 10 pre-existing errors/2 warnings,
                                       identical before and after this
                                       change (confirmed via git stash) —
                                       zero new lint issues introduced
```

12 new backend tests cover: online when ACTIVE, rejected when
PENDING_REVIEW, rejected-but-can-go-offline when SUSPENDED, session
persisted on going online, session closed on going offline, idempotent
repeated online calls, concurrent online calls (no duplicate open
sessions), summary strictly scoped to the caller, summary's online-hours
computed from persisted sessions, admin fleet endpoint rejects non-Admin,
admin fleet endpoint returns real counts + honest "Location unavailable",
admin dashboard's onlineDrivers distinguishes presence from approval
status. Plus 2 WebSocket tests: non-Admin `subscribe:fleet` rejected,
Admin `subscribe:fleet` receives real `driver:online`/`driver:offline`
events triggered by the HTTP presence toggle.

An unrelated pre-existing bug was found and fixed in the process: an
invalid `openapi.yaml` was crashing the *entire* test suite at import time
(an unquoted comma inside a YAML flow mapping). Fixed (two lines quoted);
confirmed via `git stash` that this bug pre-dated this change and that
fixing it introduced no other change (100 tests pass before this fix would
have been 0/88 collected, all failing at import).

**Flutter (`driver_app`, `admin_app`)** — **could not be run**. This
environment has no Flutter or Dart SDK installed (`which flutter dart`
resolves to nothing; matches `TODO.md`'s existing note that Flutter
QA is blocked in this environment). `flutter analyze` and `flutter test`
were not executed and no claim is made that they pass — this is a genuine
gap, not a fabricated result. Widget/unit tests were written
(`driver_app/test/driver_home_screen_test.dart`,
`admin_app/test/dashboard_screen_test.dart`) covering loading, loaded
(real values, not the old hardcoded ₦18,400/6/5h20m or the admin app's old
112), empty ("No activity yet" / "No drivers online right now"), error,
and retry states, using `package:http/testing.dart`'s `MockClient` (no
new dependency beyond `http` itself) — but they need a real Flutter SDK to
confirm they compile and pass. **Recommend running
`flutter pub get && flutter analyze && flutter test` in both apps on a
machine with the Flutter SDK before merging**, since the new `pubspec.yaml`
dependency (`http: ^1.2.2`) and all new/edited `.dart` files here are
unverified by an actual Dart analyzer.

## 10. AWS / Cognito / Stripe — intentionally deferred, not treated as defects

- No AWS resources were created, modified, or deployed.
- Neither Flutter app has Cognito sign-in wired up — `AuthTokenProvider`
  (in both apps' new `lib/services/auth_session.dart`) is the seam a real
  Cognito integration plugs into; `NoAuthTokenProvider` is a placeholder
  that fails honestly ("You need to sign in again.") rather than faking a
  session. This is the same launch-blocking gap already tracked in
  `docs/PRD.md` §9/§10 ("Live backend integration") — not new, not
  resolved by this change, not a regression.
- No Stripe changes were made; `PLATFORM_FEE_PERCENT` is reused from the
  existing payout calculation, not a new billing concept.

## 11. Genuinely remaining local work

- Run `flutter pub get`, `flutter analyze`, `flutter test` for both
  `driver_app` and `admin_app` on a machine with the Flutter SDK (see §9).
- `admin_app`'s driver list/detail screens (approve, suspend) are still on
  mock data — out of scope here, tracked in `docs/PRD.md` §9/§10 as part of
  the broader "connect the apps to the real backend" work.
- Acceptance-rate reporting (Part 9) needs an actual offer/dispatch design
  before it can be built — see §7.
- "Rides this week" / "Recent trips" on the admin dashboard remain mock —
  no backend reporting endpoint exists for them yet (unrelated to
  presence/monitoring).

## 12. Files changed

Backend: `prisma/schema.prisma`, new migration
`prisma/migrations/20260824173447_add_driver_presence/`, new
`src/services/presence.ts`, `src/services/payouts.ts` (exported the
existing commission rate), `src/routes/drivers.routes.ts`,
`src/routes/admin.routes.ts`, `src/routes/trips.routes.ts`,
`src/realtime/hub.ts`, `src/realtime/server.ts`, `src/test/helpers.ts`,
`openapi.yaml`, plus test files `src/routes/drivers.routes.test.ts`,
`src/routes/admin.routes.test.ts`, `src/realtime/realtime.test.ts`.

`driver_app`: `pubspec.yaml` (+`http`), new
`lib/services/auth_session.dart`, new `lib/services/driver_api.dart`,
`lib/views/home/driver_home_screen.dart`, `lib/views/shell/driver_shell.dart`,
new `test/driver_home_screen_test.dart`.

`admin_app`: `pubspec.yaml` (+`http`), new
`lib/services/auth_session.dart`, new `lib/services/admin_api.dart`,
`lib/views/dashboard/dashboard_screen.dart`, new
`test/dashboard_screen_test.dart`.

Docs: `docs/PRD.md` (§9.1 added), `docs/realtime-architecture.md`
(RT-05 + wire protocol additions).

## Commit SHA

See the commit that adds this file on branch `claude/ravelgo-prd-wu3xd9`.
