# RavelGo — Driver App Real Matching Integration

Follow-up to `POST_MOCK_INTEGRATION_READINESS.md` (commit `ccf4c70`), which identified driver_app's
ride-matching flow as the one remaining blocker to a real rider-to-driver ride: the rider side
(user_app) and admin side were already real, the backend matching engine was already real and
tested, but driver_app's own UI still ran an explicit local simulation with a "Simulate incoming
ride request" button. This task replaces that simulation with the real backend/API/WebSocket flow.

## 1. Executive verdict

**READY — REAL RIDE MATCHING VERIFIED**

A real rider request now results in a real backend match, a real driver-app assignment (discovered
via polling and a best-effort WebSocket push), a real driver acceptance/decline, and a real database
state change, proven end-to-end against the real local Postgres instance. This verdict is scoped to
ride matching specifically, per this task's objective — see Section 11 for the separate question of
overall AWS/Cognito/Stripe readiness, which is not yet reached (other pre-existing driver_app gaps
outside ride matching remain, listed in Section 10).

## 2. BEFORE — what was simulated

- `driver_home_screen.dart` had a hardcoded `_demoRequest` (`RideRequest` model, fixed rider name
  "Amaka O.", fixed fare, fixed pickup/destination) and a button literally labeled **"Simulate
  incoming ride request"** that opened `IncomingRequestSheet` with that fake data — no backend call
  of any kind.
- `active_trip_screen.dart`'s own code comment stated: *"This ride flow is still a local
  simulation... not a real backend Trip."* It advanced through 4 fabricated local stages
  (`toPickup` → `arrivedPickup` → `inProgress` → `arrivedDestination`) on button taps alone, with no
  status ever sent to the backend.
- `IncomingRequestSheet` had a 15-second countdown that auto-declined (no real "offer" concept
  exists — Ride matching has no expiring-offer state), and a "Negotiate final fare" control whose
  "Send to rider" button updated only local state and contacted no endpoint.
- `TripCompleteScreen` fabricated a 15% "RavelGo service fee" split (no such field exists anywhere
  in the backend's `Payment` model) and a "Rate your rider" star control with no submission endpoint
  behind it — Rider/User has no rating field in this schema at all.
- The online/offline switch on `driver_home_screen.dart` only ever flipped local
  `DriverProfile.isOnline` state — **the backend had no presence concept whatsoever**: `Driver` had
  no `online` column, and `services/matching.ts`'s eligible-driver query considered any
  `status: "ACTIVE"` (admin-approved) driver a match candidate regardless of whether their app was
  even open. An offline driver could, in the pre-existing code, still be matched to a real ride.
- `driver_profile.dart`'s `DriverProfile` had a hardcoded default constructor
  (`firstName: "Thelma"`, `lastName: "Ibeh"`, `rating: 4.8`, `totalTrips: 214`, ...) that
  `DriverShell` used unconditionally — `driverApi.getMyProfile()` existed but was never called, and
  even if it had been, `GET /api/drivers/me` didn't include the `user` relation, so no real
  name/email/phone was retrievable at all.
- There was no backend mechanism for a driver to discover a match at all: matching is fully
  synchronous and server-side (`services/matching.ts`), with no "browse available rides" or "accept
  a ride" endpoint the way Courier has — a driver had no way to learn a match happened.

## 3. AFTER — what is now real

- `DriverSession` (mirroring the exact singleton pattern already proven for `RideSession` in
  user_app) polls `GET /api/drivers/me/assignment` every 5 seconds while the driver is online and
  free, and maintains a best-effort authenticated WebSocket connection subscribed to the driver's own
  assignment channel for near-instant delivery. The moment a real `ACTIVE` `RIDE` assignment appears,
  it fetches the full `Trip` via `GET /api/trips/:id` and exposes it as `pendingRideAssignment` —
  `driver_home_screen.dart` shows `IncomingRequestSheet` automatically when this becomes non-null.
  There is no "Simulate" button anymore.
- **Accept**: re-fetches the trip to confirm it's still `MATCHED` and still assigned to this driver
  (catching a stale notification — e.g. the rider cancelled in the meantime — rather than trusting
  the earlier poll/WS event), then marks the driver busy locally. **Decline**: calls the real
  `PATCH /api/trips/:id/status {status: "CANCELLED"}` — the same ownership-checked endpoint the rest
  of the ride lifecycle uses; the backend actually releases the driver's `DriverAssignment` row.
- `ActiveTripScreen` drives the real two transitions the `Trip` schema actually has —
  `MATCHED → IN_PROGRESS → COMPLETED` — each a real `PATCH /api/trips/:id/status` call. The
  fabricated "arrived at pickup"/"arrived at destination" intermediate stages are gone; there is no
  such state in the backend.
- `TripCompleteScreen` shows the trip's real `finalFare`. The fabricated service-fee breakdown and
  rider-rating control are gone rather than kept as decoration with nothing real behind them.
- **Real backend presence**: added `Driver.online` (migration
  `20260823073714_add_driver_online_status`), `PATCH /api/drivers/me/online`, and
  `services/matching.ts` now requires `online: true` in addition to `status: "ACTIVE"` before a
  driver is matching-eligible. `driver_home_screen.dart`'s switch calls this real endpoint
  (`DriverSession.setOnline()`/`setOffline()`); the switch never shows "online" unless the backend
  actually agrees.
- **Real driver profile**: `GET /api/drivers/me` now includes the `user` relation (previously
  omitted — a real bug fixed here), and `DriverShell` loads it via `DriverSession.loadProfile()`
  before showing any tab. A driver with no backend row yet sees an honest "complete driver
  onboarding" state rather than a fabricated name.
- **Real assignment-discovery push**: extended the existing single WebSocket hub (not a second
  messaging system) with one more room type — `driverRooms`, joined via a new `subscribe_driver`
  message that resolves the room from the connection's own verified identity (no id ever accepted
  from the client, so a driver can only ever subscribe to their own channel). `POST /api/trips`
  broadcasts `driver:assignment` to the matched driver's room the instant matching succeeds.

## 4. API MAP

```
Driver UI (driver_home_screen.dart / incoming_request_sheet.dart / active_trip_screen.dart)
        |
DriverSession (services/driver_session.dart)
        |
ApiClient (services/api/api_client.dart)  — bearer token, error normalization
        |
        +-- PATCH /api/drivers/me/online         -> drivers.routes.ts       -> prisma.driver.updateMany  -> Postgres (Driver.online)
        +-- GET   /api/drivers/me                -> drivers.routes.ts       -> prisma.driver.findFirst   -> Postgres (Driver + User)
        +-- GET   /api/drivers/me/assignment      -> drivers.routes.ts       -> prisma.driverAssignment.findFirst -> Postgres
        +-- GET   /api/trips/:id                  -> trips.routes.ts        -> prisma.trip.findUnique    -> Postgres
        +-- PATCH /api/trips/:id/status            -> trips.routes.ts        -> prisma.$transaction (conditional updateMany + releaseDriver) -> Postgres
                                                          |
                                              services/matching.ts (POST /api/trips, rider-initiated)
                                              requires Driver.status=ACTIVE AND Driver.online=true
                                              AND no ACTIVE DriverAssignment (SERIALIZABLE transaction)
```

Every decision — who gets matched, whether a transition is legal, whether the driver owns the trip —
is made and enforced backend-side. `DriverSession` only asks and mirrors the answer; it contains no
matching logic of its own.

## 5. WEBSOCKET MAP

```
DriverSession._connectWs()
        |
wss://<host>/ws?token=<Cognito access token>        (realtime/server.ts)
        |
{"type": "subscribe_driver"}  ---->  handleSubscribeDriver()
                                          resolves driverId from the connection's OWN verified
                                          identity (never a client-supplied id) -> joinDriverRoom()
                                          <---- {"type": "subscribed_driver", "driverId": "..."}

matchDriverToTrip() succeeds (inside POST /api/trips)
        |
broadcastDriverAssignment(driverId, "RIDE", tripId)   (realtime/hub.ts)
        |
        <---- {"type": "driver:assignment", "assignmentType": "RIDE", "assignmentId": "<tripId>"}
                (sent only to that driver's own room — proven not to leak to another
                 driver's connection in realtime.test.ts)
        |
DriverSession._onWsMessage() triggers an immediate _poll() — the WS message itself carries no
trip details, the same "something changed, go re-fetch" shape as the rider side's trip:status —
polling (GET /api/drivers/me/assignment, every 5s) is the always-correct primary mechanism this
overlays; a WS connect/ready failure is caught and never breaks assignment discovery.
```

## 6. RIDE LIFECYCLE (driver-facing)

| State | Reached by | Backend endpoint | Driver UI |
|---|---|---|---|
| (none) | — | — | Online, "Listening for ride requests..." |
| `MATCHED` | Real-time rider request, server-side matching | `POST /api/trips` (rider) | `IncomingRequestSheet` shown automatically |
| `MATCHED` (confirmed) | Driver taps Accept | `GET /api/trips/:id` (re-confirm) | `ActiveTripScreen`, "Start trip" |
| `IN_PROGRESS` | Driver taps "Start trip" | `PATCH /api/trips/:id/status {IN_PROGRESS}` | "Complete trip" |
| `COMPLETED` | Driver taps "Complete trip" | `PATCH /api/trips/:id/status {COMPLETED, finalFare}` | `TripCompleteScreen`, real fare shown |
| `CANCELLED` | Driver taps Decline (before starting) | `PATCH /api/trips/:id/status {CANCELLED}` | Sheet dismissed, driver stays available |

Illegal transitions (e.g. completing a trip still `MATCHED`, or a driver who isn't the trip's
assigned driver attempting any of the above) are rejected server-side with 409/403, per the
pre-existing `TRIP_ALLOWED_FROM` state machine and ownership check in `trips.routes.ts` — unchanged
by this task, exercised by the new tests below.

## 7. CONCURRENCY RESULTS

Ride matching has **no multi-driver race to test** the way Courier's browse-and-claim flow does: a
new `Trip`'s eligible-driver query and its `DriverAssignment` reservation run inside one
`SERIALIZABLE` Postgres transaction (`services/matching.ts`), so exactly one driver is ever
considered per trip, atomically, before any driver's app even learns the trip exists — there is no
"offer" a second driver could also be racing to accept. This is confirmed, not assumed: the
pre-existing test `"POST /api/trips: two riders racing with exactly one ACTIVE driver free — the
driver is matched to only one trip"` (`trips.routes.test.ts`) still passes with the new `online: true`
requirement added to its fixture, proving the single-driver-single-match guarantee holds under real
concurrent load.

What **was** tested for this task, both passing:

- **Ride ↔ Courier ↔ Rental exclusivity** (pre-existing `cross-domain-concurrency.test.ts`, fixture
  updated to include `online: true` so the ride side of the race is actually possible): a driver
  racing a real ride-match against a real rental-activation — exactly one wins, exactly one
  `ACTIVE` `DriverAssignment` row exists afterward, proven via `Promise.all` against the real
  Express app and Postgres.
- **Driver-room isolation** (new, `realtime.test.ts`): two real, separately-authenticated WebSocket
  connections for two different online drivers; a real `POST /api/trips` matches one of them; only
  the matched driver's socket receives `driver:assignment` — the other driver's connection is
  confirmed to receive nothing, over a real network connection (not an in-process mock).

## 8. TEST RESULTS (exact)

| Check | Result |
|---|---|
| Backend `npm test` (unit + integration + all e2e, real Postgres, `--test-concurrency=1`) | **218 / 218 passed**, 0 failed |
| Backend `npm run typecheck` | Clean, 0 errors |
| Backend `npm run lint` (ESLint) | Clean, 0 errors/warnings |
| `npx prisma migrate status` | 7 migrations found (+1 this task: `add_driver_online_status`), schema up to date |
| `openapi.yaml` | Valid YAML, 75 documented paths (+2 this task) |
| `driver_app` — `flutter analyze` | 0 errors, 0 warnings |
| `driver_app` — `flutter test` | **48 / 48 passed** (+10 new: `driver_session_ride_matching_test.dart`; existing `driver_home_gating_test.dart` updated for the real screen API) |
| `user_app` — `flutter analyze` / `flutter test` | 0 errors/warnings; **48 / 48 passed** (unaffected by this task) |
| `admin_app` — `flutter analyze` / `flutter test` | 0 errors/warnings; **59 / 59 passed** (unaffected by this task) |
| `driver_app` — `flutter build web --release` | **Not available** — this project has no `web/` platform directory (never configured; android/ios only). Not added, to avoid unrelated platform-scaffolding scope creep. |

**New backend E2E tests** (`backend/src/e2e/driver-ride-matching.e2e.test.ts`, real HTTP against the
real Express app + real Postgres, Cognito JWT signature verification stubbed the same way the
repo's existing 200+ tests already do):

1. *Full 15-step lifecycle*: driver bootstraps and goes online (real presence persisted) → confirms
   no assignment yet → rider requests a real trip → backend auto-matches → driver discovers it via
   the real polling endpoint → confirms it via `GET /trips/:id` → verifies the `DriverAssignment` row
   directly in Postgres → rider independently sees `MATCHED` → driver progresses `IN_PROGRESS` →
   rider sees the update → driver completes with a real `finalFare` → independent Postgres re-read
   confirms `COMPLETED` → the `DriverAssignment` is confirmed released → a fresh poll confirms the
   driver is available again.
2. *Decline*: a driver releases a real `MATCHED` trip via the real status endpoint; the
   `DriverAssignment` is confirmed released in Postgres.
3. *Offline enforcement*: an `ACTIVE` but never-toggled-online driver is proven to never be matched —
   the trip stays `REQUESTED` — confirming `online` has a real effect on matching, not just on the
   local UI.

**New unit tests** (`driver_app/test/driver_session_ride_matching_test.dart`, `MockClient`-driven,
same pattern as user_app's `ride_session_test.dart`): profile loading (success and honest-404),
`setOnline`/`setOffline` (success, failure, and "offline never interrupts a busy driver"), the full
poll → discover → accept → confirm → mark-busy path, and decline → PATCH CANCELLED → clear.

## 9. SECURITY RESULTS

No existing authentication, authorization, ownership, suspension, rate-limiting, or concurrency
control was weakened. Both new endpoints require the `Driver` Cognito group and are self-scoped via
`req.user!.sub` — there is no id parameter a driver could substitute to reach another driver's data:

- A driver cannot see another driver's assignment: `GET /api/drivers/me/assignment` derives the
  driver row from the caller's own `cognitoSub`; there is no `:id` variant.
- A driver cannot subscribe to another driver's WebSocket assignment channel: `subscribe_driver`
  accepts no id from the client at all — proven with a real two-connection test (Section 7).
- A driver cannot accept/modify/complete another driver's trip: `PATCH /api/trips/:id/status`'s
  pre-existing ownership check (`existing.driverId !== driver.id → 403`) is unchanged and still
  covered by its existing tests.
- A driver cannot bypass the online/availability check: it lives in `services/matching.ts`'s driver
  query itself, not in any client-controllable input.
- A suspended driver is still blocked by the pre-existing, unchanged `requireAuth` suspension check
  (HTTP) and the WS server's own equivalent check at connect time.

**No remaining security issues identified** in the ride-matching flow itself.

## 10. Remaining blockers

**Local** (pre-existing, outside this task's ride-matching scope, unchanged by this pass):

- driver_app's My Trips (`mockTrips`) and My Documents (`mockDocuments`) screens still render
  hardcoded arrays despite corresponding backend endpoints existing.
- driver_app's onboarding flow (create account → driver/vehicle info → verify) still collects input
  it never submits to `POST /api/drivers/me`.
- driver_app's map is still a static `assets/fake_map.png` image; `google_maps_flutter` remains an
  unused dependency.
- driver_app's Earnings screen, Ratings, Incentives, and Preferences screens remain static demo
  content (no backend endpoints exist for most of these yet).
- user_app's "Ravel driver portal" duplicate section, "Services" (car-rental marketplace),
  Subscription purchase flow, and Delete Account no-op — all previously documented in
  `POST_MOCK_INTEGRATION_READINESS.md` — remain as documented there.
- `backend/src/services/payouts.ts`'s `processPayout` still fabricates a Stripe transfer.

**Cognito**: `COGNITO_USER_POOL_ID`/`COGNITO_CLIENT_ID` are still placeholder values — no real
device sign-in, and the WebSocket driver-assignment push (though now real and tested against a real
local WS server) has not been proven with a genuine Cognito-issued token, since none can be produced
in this environment.

**AWS**: no RDS/App Runner/S3/CloudFront/CloudWatch provisioned — intentionally, per this task's
explicit instructions. Everything above was validated against local Postgres and a local dev
process only.

**Stripe**: unchanged from the previous report — driver payout processing and both apps' subscription
purchase flows remain simulated; no Stripe keys are configured, per this task's explicit
instructions.

## 11. Final recommendation

Ride matching itself — the specific, narrow objective of this task — is done: a real rider request
now reliably produces a real driver-visible assignment, a real accept/decline, and a real completed
trip, proven end-to-end against the real backend and Postgres, with no client-side matching logic and
no remaining simulation in that flow. **RavelGo should not yet proceed to the AWS/Cognito/Stripe
integration phase**, however — Section 10's Local blockers (most notably driver_app's own
onboarding, My Trips/Documents, and the user_app items carried over from the previous report) are
still real gaps a driver or rider would encounter today. The next logical step is closing those
remaining Local blockers — driver onboarding submission and My Trips/My Documents wiring are the
highest-value next targets, since they follow the exact same proven pattern (`DriverApi`/`RideApi`
calls already exist for most of them) this task and the previous one both used — before treating the
three Flutter apps as feature-complete against the local backend and moving to Cognito.

---

**Final commit**: to be recorded after this report is committed and pushed (see final message).

**Files changed this pass**: backend (`schema.prisma` + migration, `matching.ts`, `drivers.routes.ts`,
`trips.routes.ts`, `realtime/hub.ts`, `realtime/server.ts`, `openapi.yaml`, plus test-fixture updates
in `trips.routes.test.ts`/`cross-domain-concurrency.test.ts`/`ride-lifecycle.e2e.test.ts` for the new
`online` requirement, and 2 new test files); driver_app (`driver_session.dart` rewritten,
`driver_profile.dart` rewritten, `driver_api.dart`/`ride_api.dart`/`api_client.dart` extended,
`driver_home_screen.dart`/`active_trip_screen.dart`/`incoming_request_sheet.dart`/
`trip_complete_screen.dart`/`driver_shell.dart` rewritten, `ride_request.dart` deleted, 2 test files
updated/added, `pubspec.yaml`/`pubspec.lock` gained `web_socket_channel`).
