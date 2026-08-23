# VEHICLE_IMAGE_AND_DEMO_DATA_READINESS

**All records described in this document are development/demo data and are
not production users or businesses.**

This task added real vehicle-photo capability to the existing `Vehicle`
model/API and wired it through all three Flutter apps, then extended the
existing demo inventory (added by a prior task) so the three demo vehicles
carry a real photo and one demo driver is genuinely available for live
ride-dispatch / courier-accept testing. No new vehicle/rental/booking/upload
models, routes, or API clients were created — every change reuses the
existing `Vehicle`, `RentalListing`, `RentalBooking`, `Trip`,
`CourierRequest`, `TripOffer`, and `DriverAssignment` models and the
existing S3 presign endpoint. No AWS infrastructure, Cognito, or Stripe work
was touched.

## 1. Vehicle image architecture

- **Schema**: `Vehicle.imageUrl String?` (nullable, no default) — migration
  `20260823151313_add_vehicle_image_url` (`ALTER TABLE "Vehicle" ADD COLUMN
  "imageUrl" TEXT;`). Every existing vehicle row keeps `NULL`; nothing was
  backfilled or guessed.
- **Upload path (real, production-shaped)**: reuses the existing generic S3
  presign endpoint (`POST /uploads/presign`, bucket `"assets"` — this bucket
  already existed and was already commented as being for "vehicle/rental
  photos," it just had nothing wired to it). A client PUTs the photo bytes
  straight to S3, then sends the resulting `imageKey` to
  `POST /vehicles` or `PATCH /vehicles/:id`.
- **Ownership check**: `imageKey` must start with `${callerSub}/` — every
  key `POST /uploads/presign` mints is already namespaced that way, so
  anything else was never issued to the calling user. Rejected with 403
  before the vehicle is touched (`vehicles.routes.ts`'s
  `resolveOwnedImageUrl`), the exact same pattern `documents.routes.ts`
  already uses for `DriverDocument.fileKey`.
- **Resolution seam** (`backend/src/services/assets.ts`,
  `resolveAssetUrl`): if the new optional env var `ASSETS_PUBLIC_BASE_URL`
  (the CloudFront domain from `infra/lib/storage-stack.ts`'s
  `AssetsDistributionDomain` output) is configured, the key is joined onto
  it into a real, loadable URL. **It is not configured anywhere in this
  repo or in this task** — AWS doesn't exist yet — so today the function
  returns the bare key unchanged rather than fabricating a URL that would
  404. This is the honest "configuration seam so the real S3 URLs can be
  supplied later" the task asked for, not a working production upload path;
  see §13.
- **Local dev/demo representation**: three small, clearly-labeled placeholder
  PNGs (procedurally drawn, not real vehicle photography — each stamped
  "DEMO IMAGE — NOT A REAL VEHICLE PHOTO") live at
  `backend/public/demo-vehicles/` and are served at `/demo-assets/*` via a
  new `express.static` mount in `app.ts` (a few lines, clearly commented as
  demo-only — not the real upload/serving pipeline). Only the three seeded
  demo vehicles use this path; a real driver-uploaded photo never goes
  through it.
- **Flutter resolution**: each app's `ApiClient` gained a `resolveAssetUrl`
  method — a relative path (the demo case, e.g.
  `/demo-assets/demo-bmw-7-series.png`) is prefixed with `API_BASE_URL`
  exactly like every other API path already is; an absolute `http(s)` URL
  (the real S3/CloudFront case, once deployed) is returned unchanged.

## 2. API changes

- `POST /vehicles`, `PATCH /vehicles/:id`: accept an optional `imageKey`
  (write-only), resolved server-side into `imageUrl`. Omitting it leaves the
  vehicle's photo unchanged (a `PATCH` with no `imageKey` never wipes an
  existing photo). No new routes, no new API client — the same
  `vehicles.routes.ts` / `VehicleApi` as before.
- `GET /vehicles/me`, and `GET /rentals` (via its existing
  `include: { vehicle: true }`): now include `imageUrl` on every vehicle,
  automatically — no route change needed there.
- OpenAPI (`openapi.yaml`): `VehicleInput.imageKey` (write-only, documented
  ownership rule) and `Vehicle.imageUrl` (read-only) added; `403` response
  documented on both vehicle endpoints. Verified the full document still
  parses via `js-yaml` and loads through the same code path `app.ts` uses at
  boot (exercised implicitly by the passing backend test suite, which
  imports `app.ts`).

## 3. Flutter changes

- **driver_app** — `models/vehicle.dart` gained `imageUrl`; `vehicle_api.dart`
  gained `uploadImageAndAttach()` (presign → S3 PUT → `PATCH .../imageKey`),
  mirroring the existing `document_api.dart` upload flow exactly.
  `vehicle_list_screen.dart` ("My Vehicles") now shows each vehicle's real
  photo, or a clean "No vehicle photo" placeholder — never a stand-in image.
  `add_vehicle_screen.dart` gained an optional photo picker
  (`PickableUploadBox`, the same widget the driver-document upload flow
  already uses) — the vehicle is created first, then the photo is uploaded
  and attached; a photo-upload failure doesn't block saving the vehicle, and
  is surfaced honestly rather than pretended away.
- **admin_app** — `models/rental_listing.dart` gained `vehicleImageUrl`
  (from the listing's nested `vehicle.imageUrl`, already returned by the
  existing `GET /rentals`); `rental_listings_screen.dart` now shows the real
  photo or the same placeholder pattern.
- **user_app** — `views/Services/CarListing.dart` was rewritten from a
  hardcoded 4-item `carList` (`assets/car1.png`…`assets/car4.png`, static
  names, no backend call at all) into a real screen backed by
  `RentalApi.browseListings()` — real photo, brand/model/year/colour, daily
  rate, and location per card, for every APPROVED listing in the database.
  `car1.png`–`car4.png` are no longer referenced anywhere in the app (they
  were used only as this fake inventory) but were **not deleted**, per the
  task's own instruction not to remove assets without confirming nothing
  else needs them. Two new screens complete the real flow:
  - `BookRentalScreen.dart` — picks a start/end date and calls the existing
    `RentalApi.createBooking()`, creating a real `RentalBooking` in
    `REQUESTED` status (never a fabricated "Booked" label), and surfaces a
    real `RENTAL_OVERLAP` 409 as a clear message if the dates conflict.
  - `MyRentalBookingsScreen.dart` — the rider's real bookings via
    `RentalApi.myBookings()`, each shown in its actual status
    (REQUESTED/CONFIRMED/ACTIVE/COMPLETED/CANCELLED/REJECTED), with a real
    cancel action via the existing `cancelBooking()` for
    REQUESTED/CONFIRMED bookings.
  - `RentalApi` itself was not modified — every one of these screens calls
    methods that already existed and were simply never wired to any UI.

## 4. Three demo vehicles

Per the task's own instruction to reuse existing architecture and not reopen
previously-completed work, this reuses the three demo vehicles/drivers a
prior task already seeded (`backend/prisma/seed.ts`, `seedDemoData()`) rather
than creating a fourth parallel set. Each now carries a real `imageUrl`:

| Plate | Vehicle | Category | Owner (driver) | Photo |
|---|---|---|---|---|
| DEMO-101-LG | Mercedes-Benz E-Class, 2023, Black | Luxury sedan | Demo Driver One | `/demo-assets/demo-mercedes-e-class.png` |
| DEMO-202-LG | Toyota Land Cruiser, 2022, White | Luxury SUV | Demo Driver Two | `/demo-assets/demo-toyota-land-cruiser.png` |
| DEMO-303-LG | BMW 7 Series, 2024, Grey | Luxury executive sedan | Demo Driver Three | `/demo-assets/demo-bmw-7-series.png` |

Verified live: `GET /api/vehicles/me` (as Demo Driver One) and
`GET /api/rentals` (as Demo Rider One) both return the correct `imageUrl`
for each vehicle, and `GET /demo-assets/demo-mercedes-e-class.png` returns
`200 image/png`.

## 5. Taxi demo scenario

**Demo Driver Two** (Toyota Land Cruiser) is the fully available demo
driver: `Driver.status = ACTIVE`, `online = true`, **no active
`DriverAssignment`**. Previously (prior task) this driver was seeded busy
with a fabricated IN_PROGRESS ride; that block was rewritten into a 3rd
**completed** ride (still real trip history) and any `ACTIVE` assignment
left over from an earlier seed run is explicitly ended, so re-running the
seed against an already-seeded database converges to the same free state.

Verified live, through the real, unmodified dispatch system
(`services/matching.ts`): as Demo Rider Two, `POST /api/trips` created a
`REQUESTED` trip, and `offerNextDriver()` — the same function every real
ride request calls — matched **Demo Driver Two** and created a real
`TripOffer` row (`status: OFFERED`). Matching was **not** bypassed: the
offer only exists because Demo Driver Two genuinely satisfied every
eligibility condition (`ACTIVE`, `online`, no active trip/assignment, no
existing unanswered offer). The test offer was then declined and the test
trip cancelled through the real endpoints, restoring Demo Driver Two to its
available baseline state.

## 6. Courier demo scenario

Unchanged from the prior task's seed, and still valid: **Demo Auto Parts
(Business)**'s courier request ("Brake pads and oil filter set") sits
`REQUESTED` with no `driverId` — a real, unassigned `CourierRequest` any
eligible driver can accept via the existing `PATCH
/courier-requests/:id/accept` (`requireDriverAvailable` + `reserveDriver`,
the same code every real courier accept goes through). Demo Driver Two
(now free — see §5) is eligible to accept it live; no fake courier screen
or bypass was introduced.

## 7. Rental demo scenario

Unchanged from the prior task's seed, and still valid: all three demo
vehicles have `APPROVED` `RentalListing`s, and Demo Driver Three's listing
(BMW 7 Series) has a real, currently-`ACTIVE` `RentalBooking` for Demo Rider
Three, backed by a real `DriverAssignment` (`RENTAL`, `ACTIVE`) — created the
same way `activateBooking()` would create one for a real booking. This
listing (and the Land Cruiser's `CONFIRMED` upcoming booking) now also
render with a real photo in `user_app`'s rewired `CarListing` screen and
`admin_app`'s rental listings screen (§3).

## 8. Security validation

- **Vehicle-image ownership**: `POST /vehicles` / `PATCH /vehicles/:id`
  reject an `imageKey` not namespaced under the caller's own sub with `403`,
  before the vehicle row is created/touched — verified by 4 new backend
  tests (own key accepted and resolved; foreign key rejected on create;
  foreign key rejected on update and leaves the row unchanged; foreign key
  on a *validly-owned* update still 404s if the vehicle itself belongs to
  someone else, confirming the two ownership checks are independent).
- **Vehicle ownership** (pre-existing, unmodified): `PATCH /vehicles/:id`
  still 404s for a vehicle belonging to a different driver — untouched, and
  re-verified by the existing + new tests.
- **Admin permissions**: unaffected — `vehicles.routes.ts` is still
  `requireRole("Driver")` only; nothing in the admin routes or `Admin`
  role/scope changed.
- **Secrets**: no AWS credentials, keys, or real values were added anywhere.
  `ASSETS_PUBLIC_BASE_URL` is documented in `.env.example` as a commented-out
  placeholder, exactly like the pattern already used for `STRIPE_SECRET_KEY`
  etc.; verified via `git diff`/`git status` that only intended files
  changed and no secret-shaped value was introduced.
- **No production behavior changed**: `git diff --stat` confirms this task
  touched only vehicle/asset/rental-display code — `services/matching.ts`,
  `services/courier.ts`, `services/rentals.ts`, `middleware/auth.ts`, and
  every payment/Stripe path are untouched. The temporary, dev-only Cognito
  bypass used for live verification (§13) was reverted before finishing —
  `git status` shows zero diff on `middleware/auth.ts`.
- **No real personal data**: all demo identities remain the pre-existing
  `demo-*` / `demo.*@ravelgo.test` fixtures; nothing new was introduced.

## 9. Tests executed/results

- **Backend**: `npm test` — **247/247 pass, 0 fail** (237 pre-existing +
  10 new: 6 vehicle-image CRUD/ownership tests in
  `vehicles.routes.test.ts`, 4 `resolveAssetUrl` unit tests in the new
  `services/assets.test.ts`).
- `npm run typecheck` — clean.
- `npm run lint` — clean.
- `npx prisma validate` — schema valid.
- `npx prisma migrate status` — "Database schema is up to date!" against the
  local Postgres instance, confirming the new migration applied cleanly
  without touching existing rows.
- OpenAPI (`openapi.yaml`) — parses via `js-yaml` and loads successfully
  through `app.ts`'s own `loadYaml(readFileSync(...))` call (exercised by
  every one of the 247 backend tests, which all import `app.ts`).
- **driver_app**: `flutter analyze` — 0 errors (7 pre-existing style
  `info`s, unrelated to this change, one new one matching the same
  pre-existing pattern in `vehicle_api.dart`). `flutter test` — **56/56
  pass**.
- **admin_app**: `flutter analyze` — 0 errors (15 pre-existing style
  `info`s). `flutter test` — **59/59 pass**.
- **user_app**: `flutter analyze` — 0 errors, 0 new warnings (155
  pre-existing `info`/style items across the app's existing files, unrelated
  to this change; the 3 new/rewritten files only add the same pre-existing
  `file_names` style info the rest of this app's PascalCase-named files
  already have). `flutter test` — **48/48 pass**.
- **Live API verification** (temporary, dev-only, always-reverted Cognito
  bypass — no real Cognito pool exists yet, same technique already approved
  earlier this session): `GET /api/vehicles/me` and `GET /api/rentals` both
  return the correct `imageUrl` per vehicle; `GET /demo-assets/*.png`
  returns `200 image/png`; a real `POST /api/trips` as Demo Rider Two
  produced a real `TripOffer` for Demo Driver Two through the unmodified
  `services/matching.ts` (see §5), then was cleanly declined/cancelled
  through the real endpoints. `middleware/auth.ts` confirmed clean (no diff)
  after this verification.
- Idempotency: `npm run prisma:seed` re-run after the full test suite
  (which wipes the database via its own `resetDb()` fixture) restored the
  demo cohort correctly, including the freed Demo Driver Two and the three
  vehicle images, without duplicating anything.

## 10. Files changed

Backend:
- `backend/prisma/schema.prisma` — `Vehicle.imageUrl`
- `backend/prisma/migrations/20260823151313_add_vehicle_image_url/migration.sql` — new
- `backend/prisma/seed.ts` — vehicle `imageUrl`s; Demo Driver Two's seeded
  ride reworked into a completed trip + freed assignment
- `backend/src/config/env.ts` — `ASSETS_PUBLIC_BASE_URL`
- `backend/.env.example` — documented the new var
- `backend/src/services/assets.ts` — new (`resolveAssetUrl`)
- `backend/src/services/assets.test.ts` — new
- `backend/src/routes/vehicles.routes.ts` — `imageKey` accept/ownership/resolve
- `backend/src/routes/vehicles.routes.test.ts` — 6 new tests
- `backend/src/app.ts` — `/demo-assets` static mount
- `backend/public/demo-vehicles/*.png` — new, 3 placeholder demo images
- `backend/Dockerfile` — `COPY public ./public`
- `backend/openapi.yaml` — `imageKey`/`imageUrl` schema + 403 responses

Flutter:
- `driver_app/lib/models/vehicle.dart`, `services/api/vehicle_api.dart`,
  `services/api/api_client.dart`, `views/vehicles/vehicle_list_screen.dart`,
  `views/vehicles/add_vehicle_screen.dart`
- `admin_app/lib/models/rental_listing.dart`, `services/api/api_client.dart`,
  `views/rentals/rental_listings_screen.dart`
- `user_app/lib/services/api/api_client.dart`,
  `views/Services/CarListing.dart` (rewritten),
  `views/Services/BookRentalScreen.dart` (new),
  `views/Services/MyRentalBookingsScreen.dart` (new)

## 11. Migration created

`backend/prisma/migrations/20260823151313_add_vehicle_image_url/migration.sql`:
```sql
ALTER TABLE "Vehicle" ADD COLUMN "imageUrl" TEXT;
```
Applied via `npx prisma migrate deploy` against the local Postgres instance;
`npx prisma migrate status` confirms the database schema is up to date, and
every existing `Vehicle` row was preserved (verified: no rows lost or
altered besides the new nullable column).

## 12. Commit SHA

`8b35566` was `HEAD` before this task's commit. This task's own commit,
`d163424`, follows it on branch `claude/ravelgo-completeness-audit-873u5u`.

## 13. What remains for AWS/S3

This task deliberately stops short of anything AWS-shaped, per its own
boundary:

- **No S3 bucket, CloudFront distribution, or any AWS resource was created**
  — `infra/lib/storage-stack.ts` (already defined, pre-existing) is
  untouched, and nothing in this task deploys it.
- `ASSETS_PUBLIC_BASE_URL` is not set anywhere in this repo. Until the
  storage stack is actually deployed and that env var is set on the running
  backend, `resolveAssetUrl()` returns the bare S3 key rather than a working
  URL — a **real** driver photo upload (via `POST /uploads/presign` →
  `imageKey`) will be correctly authorized, stored, and attached to the
  vehicle, but the resulting `imageUrl` won't actually render an image until
  that env var exists in production. This is the honest, visible state the
  task asked for ("do NOT pretend S3 is operational if it is not") — not a
  bug to fix later, a deployment step to complete later.
- No AWS credentials, Cognito changes, or Stripe changes were made anywhere
  in this task.
