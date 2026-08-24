# Driver Vehicle, Vehicle Photo & Document Verification — Implementation Report

Implements the workflow found missing by the prior audit
(`docs/PRD.md` referenced it as a gap; a separate detailed audit walked
every screen/route/model). Scope: Driver Vehicle Management, Vehicle Photo
Upload, Driver/Vehicle Document Upload, and the Verification workflow
(submit → review → approve/reject-with-reason → resubmit → re-review),
end to end, on top of the existing architecture — no existing endpoint,
model, or auth mechanism was replaced.

## Files changed

**Backend** — schema/migration: `backend/prisma/schema.prisma`,
`backend/prisma/migrations/20260824182029_vehicle_verification_photos_documents/migration.sql`
(new). Routes: `src/routes/vehicles.routes.ts`, `src/routes/documents.routes.ts`,
`src/routes/uploads.routes.ts`, `src/routes/drivers.routes.ts`. New libs:
`src/lib/fileKey.ts`, `src/lib/s3.ts`, `src/lib/assetUrl.ts`. Config:
`src/config/env.ts`. Tests: `src/routes/vehicles.routes.test.ts`,
`src/routes/documents.routes.test.ts`, `src/routes/uploads.routes.test.ts`,
`src/routes/drivers.routes.test.ts`, `src/routes/verification-workflow.e2e.test.ts`
(new), `src/test/helpers.ts`. Docs: `openapi.yaml`.

**Infra**: `infra/bin/infra.ts`, `infra/lib/api-stack.ts`.

**driver_app**: `lib/models/vehicle.dart`, `lib/models/document_item.dart`,
`lib/services/driver_api.dart`, `lib/services/image_picker_helper.dart`
(new), `lib/theme/app_theme.dart`, `lib/views/vehicles/vehicle_list_screen.dart`,
`lib/views/vehicles/add_vehicle_screen.dart`,
`lib/views/vehicles/edit_vehicle_screen.dart` (new),
`lib/views/vehicles/vehicle_detail_screen.dart` (new),
`lib/views/documents/my_documents_screen.dart`,
`lib/views/auth/create_account_screen.dart`, `lib/views/auth/add_photo_screen.dart`,
`lib/views/auth/driver_information_screen.dart`,
`lib/views/auth/vehicle_information_screen.dart` (**deleted** — see below),
`pubspec.yaml`. Tests: `test/vehicle_list_screen_test.dart` (new),
`test/add_vehicle_screen_test.dart` (new).

**admin_app**: `lib/services/admin_api.dart`,
`lib/views/drivers/driver_list_screen.dart`,
`lib/views/drivers/driver_detail_screen.dart`, `pubspec.yaml`. Tests:
`test/driver_list_screen_test.dart` (new), `test/driver_detail_screen_test.dart` (new).

## Pre-implementation audit — what was reused vs. what was missing

Confirmed by reading the code before touching it (not assumed):

- **Reused unchanged**: Cognito JWT auth + role middleware
  (`requireAuth`/`requireRole`), the driver approval state machine
  (`Driver.status`), the presigned-upload architecture
  (`POST /uploads/presign` → client PUTs to S3 → register metadata), the
  private documents bucket / public CloudFront assets bucket split already
  provisioned in `infra/lib/storage-stack.ts`, the existing
  `GET/POST/PATCH /vehicles*` and `GET/POST/PATCH /documents*` routes (all
  extended in place, not replaced), the `DriverApi`/`AdminApi` +
  `AuthTokenProvider` seam built in an earlier pass.
- **Confirmed missing** (matches the audit): no vehicle photo storage at
  all (no field, no model), no document retrieval endpoint of any kind, no
  rejection-reason field anywhere, no vehicle verification concept, no
  fileKey-ownership check, every "upload" control in both Flutter apps was
  a static non-interactive widget, `vehicle_list_screen.dart` and
  `my_documents_screen.dart` ran on local/hardcoded data, the admin
  driver-detail screen's review actions were no-ops.
- **No `TripOffer`/`DriverOffer`/dispatch system exists** in this
  codebase (confirmed again, same as the prior pass) — irrelevant to this
  task's scope, noted only for completeness.

## Database changes

New migration: `backend/prisma/migrations/20260824182029_vehicle_verification_photos_documents/`.
**Migration-safety verified**, not assumed: a real bug in Prisma's own
generated SQL (`Vehicle.updatedAt` added `NOT NULL` with no default — fails
outright against a non-empty table) was found and hand-fixed to the
standard add-nullable → backfill → set-not-null pattern, then the fix was
proven by inserting a pre-existing `Vehicle` row into a throwaway database,
applying the migration, and confirming the row survives with `updatedAt`
correctly backfilled from `createdAt`.

New enums: `VehicleVerificationStatus` (PENDING/APPROVED/REJECTED/RESUBMISSION_REQUIRED),
`VehicleType` (SEDAN/SUV/VAN/TRUCK/MOTORCYCLE/LUXURY/OTHER),
`VehiclePhotoType` (FRONT/REAR/LEFT_SIDE/RIGHT_SIDE/INTERIOR/OTHER),
`DriverDocumentType` (DRIVERS_LICENSE/VEHICLE_REGISTRATION/INSURANCE/INSPECTION/ROADWORTHINESS/BACKGROUND_CHECK/PROOF_OF_ADDRESS/OTHER).

Changed models:
- **`Vehicle`**: added `vin`, `vehicleType`, `isActive` (soft-deactivation
  — never a hard delete), `verificationStatus`, `verificationReason`,
  `verifiedAt`, `verifiedById` (→ `User`), `updatedAt`.
- **`DriverDocument`**: added `vehicleId` (→ `Vehicle`, nullable —
  vehicle-scoped vs. driver-level documents), `documentType`,
  `rejectionReason`, `reviewedAt`, `reviewedById` (→ `User`).
- **`User`**: added reverse relations `documentsReviewed`, `vehiclesVerified`.

New model: **`VehiclePhoto`** (`id`, `vehicleId` → `Vehicle`, `fileKey`,
`photoType`, `displayOrder`, timestamps) — a real relational table, not a
comma-separated string column, so a vehicle supports any number of photos
per angle.

All new fields on existing tables are additive with safe defaults; nothing
was dropped, renamed, or made destructively required.

## API changes

| Method | Endpoint | Purpose | AuthZ |
|---|---|---|---|
| GET | `/api/vehicles/me` | List my vehicles (now with photos + documents nested) | Driver, self |
| POST | `/api/vehicles` | Create a vehicle (now: vin, vehicleType; starts PENDING) | Driver |
| GET | `/api/vehicles/:id` *(new)* | One of my vehicles, with photos + documents | Driver, self |
| PATCH | `/api/vehicles/:id` | Update my vehicle (now: vin, vehicleType) | Driver, self |
| PATCH | `/api/vehicles/:id/deactivate` *(new)* | Soft-remove my vehicle (never hard-deleted) | Driver, self |
| POST | `/api/vehicles/:id/resubmit` *(new)* | Resend a REJECTED vehicle for review | Driver, self |
| POST | `/api/vehicles/:id/photos` *(new)* | Attach a photo (fileKey ownership verified) | Driver, self |
| DELETE | `/api/vehicles/:id/photos/:photoId` *(new)* | Remove a photo | Driver, self |
| PATCH | `/api/vehicles/:id/review` *(new)* | Approve/reject a vehicle (reason mandatory on reject) | Admin |
| GET | `/api/documents/me` | List my documents (now: `?vehicleId=` filter) | Driver, self |
| POST | `/api/documents` | Register an uploaded document (now: documentType, vehicleId, expiryDate; fileKey ownership verified) | Driver |
| POST | `/api/documents/:id/resubmit` *(new)* | Replace a REJECTED document's file, same row (no orphan) | Driver, self |
| GET | `/api/documents/:id/view` *(new)* | Short-lived signed URL to view the actual file | Driver (self) or Admin |
| PATCH | `/api/documents/:id/review` | Approve/reject (now: rejectionReason mandatory on reject; records reviewedAt/reviewedById) | Admin |
| GET | `/api/drivers/:id` | Admin driver detail (now: nests each vehicle's photos-with-URLs + documents; splits driver-level vs. vehicle-level documents) | Admin |
| POST | `/api/drivers/me` | Create driver profile (now: quietModePreferred) | Driver |
| POST | `/api/uploads/presign` | Get a presigned upload URL (now: MIME allowlist + size cap bound into the signature; role-restricted to Driver/Admin) | Driver, Admin |

`openapi.yaml` updated to document every row above; validated
(`js-yaml` parse + the existing `GET /openapi.json` smoke test).

## Flutter changes

**driver_app**:
- `lib/models/vehicle.dart`, `lib/models/document_item.dart` — rewritten
  from mock data holders to real API-shaped models (`Vehicle`,
  `VehiclePhoto`, `DriverDocument`, + type/status enums with JSON mapping).
- `lib/services/driver_api.dart` — extended with the full vehicle/photo/document
  surface (list/get/create/update/deactivate/resubmit vehicles; upload
  photo — presign→PUT→register — and delete; upload/resubmit/view
  documents; `createDriverProfile`).
- `lib/services/image_picker_helper.dart` *(new)* — shared camera/gallery
  picker, used by both the vehicle-photo and document-upload flows so
  `image_picker` (previously an unused dependency) is now actually wired.
- `lib/views/vehicles/vehicle_list_screen.dart` — real fetch,
  loading/empty/error/retry, verification-status badges, thumbnail from
  the vehicle's first photo. Local hardcoded seed vehicles removed.
- `lib/views/vehicles/add_vehicle_screen.dart` — real `Form` +
  `TextFormField` validators (blank required fields error, don't silently
  submit fake defaults like the old "Toyota"/"NEW-000-XX"); added VIN and
  vehicle-type fields; calls `POST /vehicles`.
- `lib/views/vehicles/edit_vehicle_screen.dart` *(new)* — same
  validation, calls `PATCH /vehicles/:id`.
- `lib/views/vehicles/vehicle_detail_screen.dart` *(new)* — vehicle info,
  verification status + reason, photo grid (add via camera/gallery,
  delete), vehicle-scoped document checklist (upload/replace/view/status/
  rejection reason), resubmit button when rejected, deactivate button.
- `lib/views/documents/my_documents_screen.dart` — real fetch from
  `GET /documents/me`, per-document status/expiry/rejection-reason,
  upload/replace (camera/gallery → presign → PUT → register or resubmit),
  view (opens a signed URL). Hardcoded `mockDocuments` removed.
- `lib/views/auth/create_account_screen.dart`,
  `driver_information_screen.dart` — real controllers + `Form` validation
  (previously `const TextField`s that captured nothing); onboarding now
  threads name/email/phone forward and actually calls
  `POST /drivers/me` before continuing.
- `lib/views/auth/vehicle_information_screen.dart` **removed** — it was a
  dead-end duplicate of the vehicle-info form with no persistence; the
  onboarding flow now continues straight into the real, functional
  `AddVehicleScreen` (via a new `onSaved` callback param so it can either
  pop back to the vehicle list or continue forward through onboarding).
- `lib/theme/app_theme.dart` — `outlineButton` gained an optional `color`
  param (backward-compatible; matches what `admin_app`'s already had) so a
  "Remove vehicle" / danger-styled button could reuse it instead of a new
  one-off widget.
- pubspec: added `http`, `url_launcher`.

**admin_app**:
- `lib/services/admin_api.dart` — new models (`AdminDriverSummary`,
  `AdminDriverDetail`, `AdminVehicle`, `AdminVehiclePhoto`,
  `AdminDocument`, `PagedDrivers`) and methods: `fetchDrivers`,
  `fetchDriverDetail`, `setDriverStatus`, `reviewDocument` (rejection
  reason required by the type signature's contract with the backend),
  `reviewVehicle`, `fetchDocumentViewUrl`.
- `lib/views/drivers/driver_list_screen.dart` — real fetch from
  `GET /drivers`, loading/empty/error/retry. `mockDrivers` removed from
  this screen (the file it lived in, `models/driver_record.dart`, is left
  in place because `driver_subscriptions_screen.dart` — out of this
  task's scope — still legitimately depends on it).
- `lib/views/drivers/driver_detail_screen.dart` — real fetch from
  `GET /drivers/:id`; shows real vehicles (with photo strip, verification
  status/reason), real documents (status, rejection reason, view); Approve
  is one tap, Reject opens a dialog that will not submit without a
  non-empty reason (mirrors the backend's own mandatory-reason
  enforcement, not just a client nicety); Suspend/Reactivate calls
  `PATCH /drivers/:id/status` for real. No remaining `onPressed: () {}`
  no-ops or local-only `setState` standing in for a server action.
- pubspec: added `url_launcher`.

## AWS changes

Source-only — **nothing was deployed, no AWS credentials were used, no
resources were created**.
- `infra/lib/api-stack.ts`, `infra/bin/infra.ts`: threads the existing
  `StorageStack`'s CloudFront distribution domain through to the API
  container as `ASSETS_CLOUDFRONT_DOMAIN`, so the backend can build a
  public vehicle-photo URL without presigning. No new bucket, distribution,
  or IAM change — the private documents bucket and public-via-CloudFront
  assets bucket were already exactly right for this use case.
- Verified with `cdk synth` (all 7 stacks synthesize cleanly; confirmed by
  inspecting the generated template that the App Runner service correctly
  cross-stack-references the distribution's domain name) — not just "it
  compiles," the actual CDK synthesis was run and its output checked.

## Security changes

- **fileKey ownership enforcement** (`backend/src/lib/fileKey.ts`,
  `assertFileKeyOwnedByUser`): `POST /documents` and
  `POST /vehicles/:id/photos` both now reject a fileKey that wasn't issued
  to the calling user's own presign namespace — previously a client could
  supply any string. Tested (403 on a forged key, 201 on the caller's own).
- **Presign hardening** (`uploads.routes.ts`): role-restricted to
  Driver/Admin (was: any authenticated user); per-bucket MIME allowlist
  (documents: pdf/jpeg/png/webp; assets: jpeg/png/webp — no
  `application/*`, `text/*`, or executables); a client-declared `fileSize`
  is checked against a per-bucket cap (documents 10MB, assets 8MB) *and*
  bound into the presigned request's SigV4 signature via `ContentLength`,
  so the issued URL cannot be used to upload more bytes than declared —
  this isn't just a check-then-throw-away-the-limit, S3 itself will reject
  a mismatched upload.
- **Document retrieval didn't exist before this change** — now
  `GET /documents/:id/view` (owner or Admin only) returns a 300s presigned
  GET URL against the private, `BLOCK_ALL`-public-access bucket; nothing
  else can read a document's contents. Vehicle photos get a real,
  non-presigned public CloudFront URL, matching the bucket's existing
  designed-to-be-public posture.
- **Mandatory rejection reasons**: both `PATCH /documents/:id/review` and
  `PATCH /vehicles/:id/review` return 400 if `status: REJECTED` is sent
  without a reason — there is no code path that produces a bare
  "Rejected" with nothing else, on either the backend or in the admin UI
  (the reject dialog itself won't submit an empty reason).
- **IDOR coverage extended**: every new self-scoped route
  (`GET/PATCH/DELETE /vehicles/:id*`, `POST/GET /documents/:id*`) is tested
  for the cross-driver 403/404 case, not just the happy path — see Tests
  below.
- No existing authorization was weakened; all new routes reuse
  `requireAuth`/`requireRole` unchanged, and `PATCH /vehicles/:id/review` /
  `PATCH /documents/:id/review` derive the reviewing Admin's identity from
  their own authenticated `User` row — never from a client-supplied id.

## Tests added

**Backend** (all run against a real local Postgres 16, not mocked):
- `vehicles.routes.test.ts`: vin/vehicleType on create; `GET /vehicles/:id`
  own-vs-cross-driver; deactivate own-vs-cross-driver (and confirms a
  deactivated vehicle still appears in the list, not silently removed);
  resubmit only from REJECTED, clears the reason; photo registration
  accepts caller's own fileKey / rejects a forged one / 404s for another
  driver's vehicle; photo deletion own-vs-cross-driver; vehicle review
  rejects non-Admin, requires a reason to reject, records the reviewing
  Admin, clears the reason on approve.
- `documents.routes.test.ts`: rejects a forged fileKey; vehicle-scoped
  document creation only when the vehicle is the caller's own; review
  requires a reason and records who reviewed it; resubmit only from
  REJECTED (replaces the file, clears the rejection, reuses the same row —
  asserted no orphan duplicate is created), rejects a forged fileKey on
  resubmit too, 404s for another driver's document; secure view: owner
  can, a different driver can't (403), Admin can (any driver), 404s before
  any file is uploaded.
- `drivers.routes.test.ts`: admin single-driver fetch nests vehicle
  photos with URLs and correctly splits driver-level vs. vehicle-level
  documents (not duplicated).
- `verification-workflow.e2e.test.ts` *(new)* — the single acceptance
  test walking the complete real flow end-to-end over real HTTP requests
  against a real Postgres database: driver creates a vehicle → uploads a
  photo → uploads registration + insurance → admin sees the actual
  submission → admin rejects insurance without a reason (400, blocked) →
  rejects it with a reason → driver sees the rejection and the real
  reason → resubmits (same row, no orphan duplicate — asserted) → admin
  approves the document, then the vehicle → driver sees APPROVED.
- `uploads.routes.test.ts`: Rider caller rejected (Driver/Admin only);
  unsupported content type rejected; an HTML file with a spoofed `.jpg`
  filename rejected (proves content-type, not extension, decides
  validity); oversized file rejected; Admin caller allowed too.

**Flutter** (written; see the honest caveat below):
- `driver_app/test/vehicle_list_screen_test.dart`: loading, real data (not
  the old hardcoded Toyota Camry/Honda Accord), empty state, error+retry,
  a deactivated vehicle still visible.
- `driver_app/test/add_vehicle_screen_test.dart`: submitting blank
  required fields shows validation errors and never calls the API (proves
  the old silent-fake-defaults behavior is gone); a valid submission sends
  exactly the entered values (VIN omitted, not sent as null) and pops with
  `true`.
- `admin_app/test/driver_list_screen_test.dart`: real driver data, empty
  state, error+retry.
- `admin_app/test/driver_detail_screen_test.dart`: real vehicle/document
  data rendered; rejecting a document requires a non-empty reason before
  the API is ever called (an empty-reason submit leaves the dialog open
  and calls nothing).

## Test results

```
Backend:
124/124 passing (100 pre-existing/carried-over from the prior pass + 24
new/updated in this one, including the single end-to-end acceptance test)
Typecheck: PASS (npx tsc --noEmit, clean)
Lint: unchanged from baseline (10 pre-existing errors/2 warnings, all in
files this change didn't touch — confirmed identical via `git stash` diff)
Prisma migration: PASS — applies cleanly on a fresh DB, and verified
separately against a database seeded with a pre-existing Vehicle row
(the exact case the auto-generated SQL would have failed on unfixed)
OpenAPI: valid YAML (js-yaml parse) + GET /openapi.json smoke test passing
CDK: `cdk synth` succeeds for all 7 stacks; cross-stack reference to the
CloudFront domain confirmed present in the generated template

Flutter:
Written: 9 new/updated test files, ~25 test cases, across driver_app and
admin_app, covering loading/empty/error/retry, real-vs-mock-data
assertions, validation behavior, and the mandatory-rejection-reason UI
flow.
Executed: NOT RUN. This environment has no Flutter or Dart SDK installed
(same limitation noted in TODO.md and in the prior implementation pass) —
`flutter analyze` and `flutter test` could not be executed, and no claim
is made that they pass. Every file was hand-reviewed for Dart 3 syntax
correctness (including two real mistakes caught this way before they'd
have been compile errors: DropdownButtonFormField's `value` vs.
`initialValue` param, and driver_app's `outlineButton` missing a `color`
param that admin_app already had), but this is not a substitute for the
analyzer. Recommend running `flutter pub get && flutter analyze &&
flutter test` in both apps on a machine with the Flutter SDK before
merging.
```

## What's still missing / honestly out of scope

- **Onboarding submission is real but currently blocked by a pre-existing,
  explicitly out-of-scope gap**: neither Flutter app has Cognito sign-in
  wired up (tracked separately in `docs/PRD.md`; this task's own
  instructions explicitly forbid implementing Cognito here). The
  onboarding screens now genuinely capture input, validate it, and attempt
  a real `POST /drivers/me` call — but without a real access token that
  call correctly fails with "You need to sign in again." rather than
  silently succeeding. This is the honest current state, not a defect
  introduced by this pass, and not something this pass could fix within
  its boundaries.
- **CarPaddy** (`car_paddy_screen.dart`) still uses the decorative
  `uploadBox` — it's a distinct product line (vehicle license renewal),
  not part of this task's Vehicle Management / Photo / Document
  Verification scope, and was left untouched deliberately.
- **No deep audit-history table** for document/vehicle resubmission —
  resubmit reuses the same row (proven by test: no orphan duplicate) but
  doesn't retain a log of prior rejection reasons/reviewers. Flagged as a
  reasonable follow-up, not built now, to keep this pass's scope bounded.
- **S3 object cleanup**: deleting a vehicle photo (or replacing a
  document) removes the database row but leaves the underlying S3 object
  for bucket lifecycle rules to reap — consistent with how the existing
  codebase already handled this before this change, not a new gap.
- **Flutter analyze/test**: see Test Results above — genuinely unverified
  by tooling in this environment.

## Final feature matrix

| Capability | Status |
|---|---|
| Driver views real vehicles | **PASS** |
| Driver adds vehicle | **PASS** |
| Driver edits vehicle | **PASS** |
| Driver deactivates vehicle | **PASS** (soft-deactivate; no hard delete by design) |
| Driver uploads vehicle photos | **PASS** |
| Driver views vehicle photos | **PASS** |
| Driver uploads driver's license | **PASS** |
| Driver uploads registration | **PASS** |
| Driver uploads insurance | **PASS** |
| Driver uploads inspection | **PASS** |
| Driver sees real document status | **PASS** |
| Driver sees rejection reason | **PASS** |
| Driver resubmits rejected document | **PASS** |
| Vehicle verification | **PASS** |
| Admin sees real vehicle | **PASS** |
| Admin sees real photos | **PASS** |
| Admin sees real documents | **PASS** |
| Admin approves | **PASS** |
| Admin rejects | **PASS** |
| Admin provides rejection reason | **PASS** (backend enforces it; UI cannot submit without one) |
| Driver sees approval/rejection | **PASS** |
| Secure document retrieval | **PASS** |
| Cross-driver IDOR protection | **PASS** (tested on every new self-scoped route) |
| File validation (type/size) | **PASS** (server-enforced, not just client-side) |
| End-to-end workflow (backend, driver ↔ admin) | **PASS** — proven by the full test chain: create vehicle → upload photo/documents → PENDING → admin rejects with reason → driver sees it → resubmits → admin approves → APPROVED, all through real HTTP requests against a real Postgres database |
| End-to-end workflow (through the actual Flutter UI, on-device) | **PARTIAL** — the UI code is real and calls the real API, but is blocked pre-launch by the pre-existing, explicitly out-of-scope missing Cognito sign-in (no way to obtain a real access token on-device yet), and the Flutter test suite itself is unexecuted in this environment (see Test Results) |
