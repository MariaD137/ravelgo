# DEMO_DATA_READINESS

**All records described in this document are development/demo data and are
not production users or businesses.**

This task extended the repository's existing seed mechanism
(`backend/prisma/seed.ts`, run via `npm run prisma:seed`) with a clearly
identified, idempotent cohort of demo data so all three RavelGo apps show
realistic activity when pointed at a local development backend, instead of
empty dashboards. No new seed system was created, no production business
logic, matching, authentication, or payment code was touched, and no
AWS/Cognito/Stripe integration of any kind was added.

## 1. Demo accounts created

**3 demo drivers** (`ravelgo_driver_app`), all `Driver.status = ACTIVE`:

| Name | Email | Online | Rating | Total trips |
|---|---|---|---|---|
| Demo Driver One | demo.driver1@ravelgo.test | true | 4.9 | 128 |
| Demo Driver Two | demo.driver2@ravelgo.test | true | 4.7 | 302 |
| Demo Driver Three | demo.driver3@ravelgo.test | false | 4.85 | 76 |

Each has 3 `DriverDocument` rows (Driver's License, Vehicle Registration,
Insurance Certificate), all `APPROVED`, matching the existing seeded
driver's document pattern.

**3 demo riders** (`ravelgo_rider_app`), role `RIDER`:

- Demo Rider One — demo.rider1@ravelgo.test
- Demo Rider Two — demo.rider2@ravelgo.test
- Demo Rider Three — demo.rider3@ravelgo.test

**3 demo businesses** — see §3 for why these are `RIDER`-role `User`
accounts, not a separate model.

All demo identities use the `demo-*` / `demo.*@ravelgo.test` convention,
distinct from the pre-existing `seed-*` / `*@example.com` fixtures the
original seed already creates (Amaka Obi, Thelma Ibeh) — those are
untouched by this task.

## 2. Demo vehicles created

Exactly 3, each owned by one demo driver, using the existing `Vehicle`
model (no new fields invented):

| Plate | Brand / Model | Year | Colour | Owner | Rental-eligible |
|---|---|---|---|---|---|
| DEMO-101-LG | Mercedes-Benz E-Class | 2023 | Black | Demo Driver One | yes (taxi + rental) |
| DEMO-202-LG | Toyota Land Cruiser | 2022 | White | Demo Driver Two | yes (taxi + rental) |
| DEMO-303-LG | BMW 7 Series | 2024 | Grey | Demo Driver Three | yes (rental; owner stays offline for taxi) |

Each is `isPrimary: true` for its owning driver (respecting the "at most
one primary vehicle per driver" convention `vehicles.routes.ts` enforces)
and `listedForRental: true`.

## 3. Demo businesses created

**No `Business` model exists in `schema.prisma`** — `CourierRequest` only
relates to a `User` sender (see the model's `senderId`/`sender` fields).
Per the task's own instruction ("use the existing courier/customer
representation that the application already supports and document what
was used"), the three demo businesses are represented as ordinary
`RIDER`-role `User` accounts acting as courier senders — the exact same
shape every other courier sender in this app already uses, not a new
concept:

| Display name | Email |
|---|---|
| Demo Luxury Boutique (Business) | demo.business1@ravelgo.test |
| Demo Auto Parts (Business) | demo.business2@ravelgo.test |
| Demo Electronics (Business) | demo.business3@ravelgo.test |

Verified in the admin app's Courier Requests screen, each request
correctly renders "Requested by Demo Auto Parts (Business)" etc. — the
`(Business)` suffix makes the representation legible without inventing UI.

## 4. Taxi/rides created

Using the real `Trip` model and its existing status values (written
directly as valid, self-consistent rows — the same approach the
pre-existing seed already uses for its one Trip — respecting every
relevant constraint: `Trip_riderId_open_unique`, vehicle/driver FKs, and
the `DriverAssignment` busy invariant):

| Rider → Driver | Route | Fare | Status |
|---|---|---|---|
| Demo Rider One → Demo Driver One | Ikeja, Lagos → Victoria Island, Lagos | ₦19.00 | **COMPLETED** (history) |
| Demo Rider Three → Demo Driver One | Yaba, Lagos → Surulere, Lagos | ₦10.00 | **COMPLETED** (history) |
| Demo Rider Two → Demo Driver Two | Lekki Phase 1, Lagos → Ajah, Lagos | ₦14.25 (estimate) | **IN_PROGRESS** (active) |

The `IN_PROGRESS` trip is backed by a real `DriverAssignment` row
(`RIDE`, `ACTIVE`) for Demo Driver Two, exactly like a real matched ride —
Demo Driver Two correctly shows as busy through the same
`GET /drivers/me/assignment` endpoint every other busy driver uses.

## 5. Courier deliveries created

Using the real `CourierRequest` model and its existing status values:

| Business (sender) → Driver | Package | Fare | Status |
|---|---|---|---|
| Demo Luxury Boutique → Demo Driver One | Designer handbag order | ₦12.00 | **DELIVERED** (completed) |
| Demo Auto Parts → *(unassigned)* | Brake pads and oil filter set | ₦8.50 | **REQUESTED** (awaiting a driver) |
| Demo Electronics → Demo Driver One | Sealed laptop, insured | ₦15.00 | **IN_TRANSIT** (active) |

Verified live: the unassigned request correctly appears in
`GET /courier-requests/available` for any eligible driver; the in-transit
one is backed by a real `DriverAssignment` (`COURIER`, `ACTIVE`) for Demo
Driver One.

## 6. Rental listings/bookings created

3 `RentalListing` rows (one per demo vehicle, all `APPROVED`), each with
one `RentalBooking`:

| Listing (vehicle) | Daily rate | Booking renter | Dates | Status |
|---|---|---|---|---|
| DEMO-101-LG (Demo Driver One) | ₦120/day | Demo Rider One | 20–17 days ago (3 days) | **COMPLETED** (past) |
| DEMO-202-LG (Demo Driver Two) | ₦150/day | Demo Rider Two | +10 to +13 days from now | **CONFIRMED** (upcoming) |
| DEMO-303-LG (Demo Driver Three) | ₦200/day | Demo Rider Three | −1 to +2 days (spans now) | **ACTIVE** (currently active) |

No two bookings share a vehicle, so no overlap exists to protect against.
`price` is computed with the same formula `services/rentals.ts` uses
(`dailyRate × ceil(days)`). The `ACTIVE` booking is backed by a real
`DriverAssignment` (`RENTAL`, `ACTIVE`) for Demo Driver Three — exactly
what `activateBooking()` would have created — so Demo Driver Three
correctly shows as busy despite being offline for taxi work.

## 7. Active / completed / upcoming summary

| Domain | Completed/past | Active/current | Upcoming/awaiting |
|---|---|---|---|
| Ride | 2 trips | 1 trip (IN_PROGRESS) | — |
| Courier | 1 delivery | 1 delivery (IN_TRANSIT) | 1 delivery (REQUESTED, unassigned) |
| Rental | 1 booking | 1 booking (ACTIVE) | 1 booking (CONFIRMED) |

Exactly one demo driver is busy in each domain (Ride / Courier / Rental)
at once — no two demo drivers compete for the same
`DriverAssignment_driverId_active_unique` slot.

## 8. Seed command

```
cd backend
npm run prisma:seed
```

This is the repository's existing, unmodified seed entry point — the demo
data is appended as a new `seedDemoData()` function called at the end of
the existing `main()`, not a second script or mechanism.

## 9. Idempotency verification

Ran `npm run prisma:seed` three times against the local Postgres instance
(a raw SQL row count after each run, filtered to `demo-*` identifiers):

| Run | users | drivers | vehicles | trips | courier | listings | bookings | assignments | documents |
|---|---|---|---|---|---|---|---|---|---|
| 1st | 9 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 18 *(bug, see below)* |
| 2nd | 9 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 18 |
| 3rd (after fix) | 9 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **9** |
| 4th | 9 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **9** |

**Bug found and fixed during idempotency testing:** the first draft used
`driverDocument.createMany({ skipDuplicates: true })`, the same call the
pre-existing seed already uses for its one driver. `DriverDocument` has no
unique constraint in the schema (`title` is free text, not a fixed enum),
so Prisma's `skipDuplicates` has nothing to deduplicate against and
silently inserts duplicates on every run — the count doubled from 9 to 18
on the second run. Fixed by switching to the same `findOrCreate({driverId,
title})` pattern used for every other non-natural-key model in this
section. Re-verified stable at 9 across two further runs after the fix.
Every other entity was stable from the first run (drivers/riders/
businesses upsert by email; the vehicle upserts by plate number; trips,
courier requests, listings, bookings, and assignments each go through
`findOrCreate` keyed on the fields that make them unique within this
fixed dataset).

## 10. Tests performed

- `npm run prisma:seed` — 4 total runs (idempotency verification above)
- `npm run typecheck` — clean
- `npm run lint` — clean (project lint scope is `src/**/*.ts`; ran
  `npx eslint prisma/seed.ts` directly too — the file isn't in that
  project's lint scope at all, same as it wasn't before this task)
- **Full backend test suite** (`npm test`, real local Postgres) —
  **237/237 pass, 0 fail** — confirms the demo seed doesn't interfere with
  or get interfered by the existing test suite's own `resetDb()` fixtures
  (they share the same local database; the test suite wipes it, and the
  demo seed was re-run afterward to restore the demo cohort for delivery)
- **Live HTTP API verification** against a running local backend
  (`GET /api/admin/dashboard`, `/api/drivers`, `/api/drivers/me`,
  `/api/drivers/me/assignment`, `/api/trips/mine`,
  `/api/courier-requests/mine`, `/api/courier-requests/available`,
  `/api/rentals`, `/api/rentals/bookings/mine`) — every seeded record
  returned correctly through the real route handlers, not read directly
  from the database. Authenticated using the same temporary, dev-only,
  always-reverted Cognito-bypass technique already established and
  approved earlier this session (no real Cognito pool exists yet — see
  `DRIVER_OFFER_ACCEPTANCE_READINESS.md` §11); removed again immediately
  after this verification, confirmed via `git diff` showing no residual
  change to `middleware/auth.ts`.
- **Browser verification of all three apps**, actually performed (not
  assumed) — headless Chromium against each app's own pre-built Flutter
  web debug build, logged in as demo accounts via the apps' own existing
  dev-only token field:
  - **driver_app**, signed in as Demo Driver One — Home shows the real
    profile (4.90 rating, 128 trips); Trips tab lists both real
    COMPLETED demo trips with correct fares.
  - **user_app**, signed in as Demo Rider One — Rides tab shows the real
    completed trip (Victoria Island, ₦19, COMPLETED).
  - **admin_app**, signed in as a fresh demo admin — Dashboard shows
    real KPIs (1 active ride, 4 online drivers, 2 pending approvals) and
    a real recent-trips feed naming the actual demo riders/drivers;
    Drivers tab lists all 3 demo drivers plus the pre-existing one;
    Courier Requests screen shows all 3 demo courier requests with
    correct statuses and "Requested by Demo Auto Parts (Business)"
    /"Demo Electronics (Business)" sender attribution; Luxury Rental
    Listings shows all 3 demo listings with correct owner/price.

## 11. Files changed

- `backend/prisma/seed.ts` — extended with a new `seedDemoData()`
  function, called once at the end of the existing `main()`. No other
  file changed. No new migration was needed — every model used already
  existed in `schema.prisma`.

## 12. Commit SHA

`1f7c740` was `HEAD` before this task's commit. This task's own commit —
containing only `backend/prisma/seed.ts` and this report — follows it on
branch `claude/ravelgo-completeness-audit-873u5u`; see the branch's latest
commit for the exact SHA.
