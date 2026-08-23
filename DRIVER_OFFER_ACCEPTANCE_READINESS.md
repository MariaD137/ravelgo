# DRIVER_OFFER_ACCEPTANCE_READINESS

Business-rule correction: separates the driver **account eligibility** state
machine (PENDING_REVIEW → ACTIVE → SUSPENDED, one-time admin approval) from
the per-ride **offer** state machine (OFFERED → ACCEPTED / DECLINED /
EXPIRED, Uber-style dispatch). This was a correction to the ride-matching
model implemented earlier in this branch (which auto-matched a trip to a
driver synchronously on request), not a rebuild of driver approval,
matching architecture, auth, WebSocket, or Flutter app structure.

## 1. What was already complete and reused

- **Driver account approval/suspension** (PENDING_REVIEW/ACTIVE/SUSPENDED,
  admin-controlled via `PATCH /drivers/:id/status`) — implemented in the
  prior task on this branch and left untouched. `driverActiveStatusError()`
  in `services/driver.ts` still gates going online, courier accept, rental
  listing/activation — this task added offer-accept to that same gate
  rather than inventing a second mechanism.
- **`DriverAssignment` / `services/driver-availability.ts`** (`reserveDriver`/
  `releaseDriver`, the partial unique index
  `DriverAssignment_driverId_active_unique`) — the busy/committed-job
  concurrency guard shared by Ride/Courier/Rental. Reused as-is for the
  moment a driver actually *accepts* an offer; never touched for the
  unanswered-offer state itself (see §6 for why).
- **WebSocket driver-room hub** (`realtime/hub.ts`'s `driverRooms`/
  `joinDriverRoom`) — reused; only a new broadcast function was added
  alongside the existing one (see §2).
- **Polling-primary architecture** (driver_app's `DriverSession`, user_app's
  `RideSession`) — reused; the driver's poll target changed from
  "assignment" to "offer" but the poll/WS-overlay pattern itself did not.
- **Serializable-transaction + conditional-`updateMany` concurrency pattern**
  (established by `reserveDriver`/`matchDriverToTrip`) — reused verbatim
  for `offerNextDriver`/`acceptOffer`.
- **Driver profile endpoint** (`GET /drivers/me`, `GET /drivers/:id`) —
  reused as the vehicle for acceptance-rate stats rather than building a
  separate stats endpoint.

No new matching engine, no new assignment/concurrency system, no new auth,
no new WebSocket transport, no AWS/Cognito/Stripe work (see §11).

## 2. What changed in this task

- **New `TripOffer` model** (`prisma/schema.prisma` +
  `prisma/migrations/20260823092845_add_trip_offer/`): `OFFERED` /
  `ACCEPTED` / `DECLINED` / `EXPIRED`, with a partial unique index
  (`TripOffer_driverId_offered_unique`) capping each driver to one
  outstanding `OFFERED` row at a time. Introduced only because
  `DriverAssignment` operates at the wrong semantic level for this: it's
  the busy/committed-job guard, and an *unanswered* offer must never make
  a driver look busy to Courier/Rental, which `DriverAssignment` cannot
  represent without corrupting that guard.
- **`services/matching.ts` rewritten**: `offerNextDriver`, `acceptOffer`,
  `declineOffer`, `expireStaleOfferIfAny`, `getAcceptanceStats` (replacing
  the old synchronous `matchDriverToTrip`).
- **New routes**: `GET /drivers/me/offer`, `PATCH /trip-offers/:id/accept`,
  `PATCH /trip-offers/:id/decline`. `POST /trips` now offers instead of
  auto-matching (still returns the trip, now `REQUESTED` with `driverId:
  null` unless nobody is eligible, same as before).
- **`realtime/hub.ts`**: new `broadcastDriverOffer(driverId, tripId)`,
  sending `{type: "driver:offer", tripId}` — kept separate from the
  pre-existing `broadcastDriverAssignment` (still used, unchanged, by
  Courier/Rental).
- **Lazy expiration**: no scheduler/queue exists in this codebase (MVP
  choice, documented in the old matcher and now `matching.ts`); a stale
  `OFFERED` row is only actually flipped to `EXPIRED` when read — by the
  offered driver's own `GET /drivers/me/offer` poll, or the rider's own
  `GET /trips/:id` poll/`cancel` call.
- **Authorization fix**: `GET /trips/:id` previously only recognized the
  trip's rider or its *assigned* driver (`trip.driverId`); a driver holding
  a live `OFFERED` offer has `trip.driverId` still null pre-accept, so they
  had no read access to pickup/destination/fare before deciding. Widened to
  also authorize a Driver-role caller holding a live offer for that trip —
  found and fixed while building real e2e coverage of the driver_app flow.
- **driver_app**: `ride_api.dart` gained `getMyOffer()`/`acceptOffer()`/
  `declineOffer()`; `driver_session.dart`'s discovery loop now polls
  `GET /drivers/me/offer` (renamed `pendingRideOffer`/`_handleOfferSeen`),
  with a one-time `GET /drivers/me/assignment` reconciliation check
  whenever tracking starts (covers "already committed before this session",
  e.g. app restart mid-ride) kept separate from offer discovery.
  `acceptPendingRide()`/`declinePendingRide()` now call the real offer
  endpoints — fixing a real bug where decline previously called `PATCH
  /trips/:id/status {CANCELLED}`, cancelling the rider's whole trip instead
  of just this driver's offer. `incoming_request_sheet.dart` shows a real
  countdown driven by the offer's own `expiresAt`, purely presentational —
  reaching zero only hides the sheet, never calls decline.

## 3. Driver account lifecycle (unchanged by this task)

```
PENDING_REVIEW --(admin approves, one-time)--> ACTIVE --(admin suspends)--> SUSPENDED
                                                  ^                              |
                                                  +----(admin un-suspends)-------+
```

`driverActiveStatusError()` blocks: going online, courier accept, rental
listing creation/activation, and (new in this task) accepting a ride offer.
None of it is touched by offer accept/decline/expiry — verified explicitly
in `driver-ride-matching.e2e.test.ts` (a PENDING_REVIEW or SUSPENDED driver
is never even offered a trip; declining/expiring never write to
`Driver.status`).

## 4. Ride offer lifecycle (new in this task)

```
POST /trips (rider)
  -> offerNextDriver(): OFFERED to one eligible driver (ACTIVE, online,
     not busy, not already holding another OFFERED row, not already
     offered this trip before)
       -> driver ACCEPTs -> Trip MATCHED, DriverAssignment reserved,
          vehicle selected at this point (not offer time)
       -> driver DECLINEs -> offer DECLINED, trip stays REQUESTED,
          offerNextDriver() runs again for the next eligible driver
       -> offer expires unanswered (20s TTL) -> lazily marked EXPIRED on
          the next read, offerNextDriver() runs again
```

Declining or expiring never touches `Driver.status`, `Driver.online`, or
any cooldown — the driver stays available for the very next offer.

## 5. Acceptance-rate calculation

`getAcceptanceStats(driverId)` in `services/matching.ts`:
`acceptedOffers / (acceptedOffers + declinedOffers + expiredOffers)`, always
computed live from `TripOffer` rows (never a separate running counter that
could drift). A currently-`OFFERED` (unresolved) offer is excluded from the
denominator. `acceptanceRate` is `null` — not `0` — when the driver has no
resolved offers yet, exposed via `GET /drivers/me` / `GET /drivers/:id`
(`acceptanceStats` field), reusing the existing profile endpoint rather than
a new stats subsystem.

## 6. Concurrency behavior

- `offerNextDriver`: Serializable transaction, backed by the partial unique
  index — a losing concurrent offer attempt gets `P2034`/`P2002`, treated
  as "no offer went out," never a 500.
- `acceptOffer`: the "still `OFFERED` and not expired" check and the write
  happen in one conditional `updateMany`; a losing concurrent accept (double
  tap, or two drivers racing — vanishingly unlikely given one offer at a
  time, but still protected) gets `count === 0` → `OfferNotAvailableError`
  → HTTP 409, never a corrupted double-write or a second `DriverAssignment`.
  Verified with a real double-tap-accept test against local Postgres
  (`driver-ride-matching.e2e.test.ts`), and with the pre-existing
  cross-domain races (Ride↔Courier, Ride↔Rental, Courier↔Rental) rewritten
  to race the real accept/activate actions instead of request creation
  (see §9 for why that rewrite was necessary, not optional).
- `DriverAssignment`'s existing concurrency architecture (`reserveDriver`/
  `releaseDriver`, its own partial unique index) is untouched and remains
  authoritative for "is this driver already committed elsewhere" —
  `TripOffer` never bypasses or duplicates it.

## 7. Driver-app behavior

Real backend data only — no simulated offers, no hardcoded driver, no fake
fare, no automatic acceptance, no fake countdown. The countdown in
`incoming_request_sheet.dart` is driven by the offer's real server-issued
`expiresAt`; reaching zero locally only hides the sheet
(`clearPendingOfferOnLocalTimeout()`) — it never calls decline, since a
local timeout is not a driver decision and recording it as DECLINE would
corrupt acceptance-rate data. The backend's own lazy expiration (triggered
by whichever side polls next) is what actually records EXPIRED.

## 8. Tests executed / results

All commands run for real in this task, none assumed:

| Suite | Result |
|---|---|
| `driver-ride-matching.e2e.test.ts` (new, 8 tests: offer→accept→complete→available again, decline→re-offer, offline/PENDING_REVIEW/SUSPENDED never offered, expiry→re-offer, acceptance-rate math, double-tap-accept concurrency) | 8/8 pass |
| `ride-lifecycle.e2e.test.ts` (rewritten for offer flow) | 2/2 pass |
| `trips.routes.test.ts` | 49/49 pass |
| `drivers.routes.test.ts` | 12/12 pass |
| `courier.routes.test.ts` | 19/19 pass |
| `rentals.routes.test.ts` | 22/22 pass |
| `cross-domain-concurrency.test.ts` (Ride↔Rental, Courier↔Rental races rewritten to race real accept/activate) | 2/2 pass |
| `realtime.test.ts` (WS `driver:offer` push test rewritten from the old `driver:assignment` expectation) | 10/10 pass |
| `openapi.routes.test.ts` | 2/2 pass |
| **Full backend suite** (`npm test`, real local Postgres) | **237/237 pass, 0 fail** |
| `npm run typecheck` | clean |
| `npm run lint` | clean |
| `npx prisma migrate status` | "Database schema is up to date!" |
| driver_app `flutter analyze` | 0 errors/warnings (6 pre-existing style infos, unrelated to this task) |
| driver_app `flutter test` (full suite, incl. rewritten `driver_session_ride_matching_test.dart`) | 56/56 pass |

No test was skipped, weakened, or deleted; existing regression tests whose
safety property depended on the old synchronous-match behavior were
restructured to test the same property against the new real actions (e.g.
a race test that used to race trip *creation* against a competing domain's
accept now races the real *offer-accept* against it, since offer creation
alone no longer commits the driver).

## 9. Files changed

Backend:
- `prisma/schema.prisma`, `prisma/migrations/20260823092845_add_trip_offer/migration.sql`
- `src/services/matching.ts` (rewritten)
- `src/realtime/hub.ts`
- `src/routes/drivers.routes.ts`, `src/routes/trips.routes.ts`
- `openapi.yaml`
- `src/e2e/driver-ride-matching.e2e.test.ts` (rewritten), `src/e2e/ride-lifecycle.e2e.test.ts`
- `src/routes/trips.routes.test.ts`, `src/routes/drivers.routes.test.ts`, `src/routes/cross-domain-concurrency.test.ts`
- `src/realtime/realtime.test.ts`

driver_app:
- `lib/services/api/ride_api.dart`
- `lib/services/driver_session.dart`
- `lib/views/riderequest/incoming_request_sheet.dart`
- `lib/views/home/driver_home_screen.dart`
- `test/driver_session_ride_matching_test.dart` (rewritten)

## 10. Remaining work, if any

None required by this task's scope. The offer/accept/decline/expire model
is implemented, tested (including real-Postgres concurrency), and wired
end-to-end from `POST /trips` through driver_app's UI. Optional, not
required by the 18-point checklist or this task's success criteria:
surfacing `acceptanceStats` in a driver-facing screen (currently returned
by the API and available to any client that wants it, but no driver_app
screen renders it yet — no screen claimed to show it before this task
either, so nothing regressed).

## 11. AWS/Cognito/Stripe items intentionally deferred

None touched, per explicit instruction. No AWS infrastructure, Cognito
integration, Stripe/payment work, or fake versions of any of them were
created or modified in this task.

## 12. Commit SHA

`8434637` — `driver_app: wire real ride-offer accept/decline, fix stale WS test`
(on top of `dd427a3` — `backend: separate driver account approval from
per-ride offer/accept` — the two commits together are this task's full
change set), branch `claude/ravelgo-completeness-audit-873u5u`.
