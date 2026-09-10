# RavelGo Backend

Unified REST API for the rider, driver, and admin apps. Node.js + Express +
TypeScript, PostgreSQL via Prisma, authenticated with Amazon Cognito JWTs.

## Endpoints (MVP slice)

- `GET /health` — unauthenticated, pings Postgres via Prisma (used by App Runner)
- `POST /api/drivers/me` (driver, creates profile on first call), `GET /api/drivers/me` (driver), `GET /api/drivers` (admin), `GET /api/drivers/:id` (admin), `PATCH /api/drivers/:id/status` (admin)
- `POST /api/riders/me` (rider, creates profile on first call), `GET /api/riders/me` (rider), `GET /api/riders` (admin), `GET /api/riders/:id` (admin), `PATCH /api/riders/:id/status` (admin)
- `POST /api/vehicles` (driver), `GET /api/vehicles/me` (driver), `PATCH /api/vehicles/:id` (driver)
- `POST /api/rentals` (driver), `GET /api/rentals/mine` (driver), `GET /api/rentals` (any authenticated user, admin sees all statuses), `PATCH /api/rentals/:id/status` (admin)
- `POST /api/support-tickets`, `GET /api/support-tickets/mine` (any authenticated user), `GET /api/support-tickets` (admin), `PATCH /api/support-tickets/:id/status` (admin)
- `POST /api/uploads/presign` (any authenticated user) — returns a short-lived S3 PUT URL + `fileKey`; upload the file client-side, then send `fileKey` to `POST /api/documents`
- `POST /api/trips` (rider — also attempts to auto-match an available driver, see Real-time below), `GET /api/trips/:id`, `PATCH /api/trips/:id/status`, `GET /api/trips` (admin), `GET /api/trips/:id/driver-location` (party to the trip — HTTP polling fallback for the WS location push)
- `GET /api/documents/me`, `POST /api/documents` (driver), `PATCH /api/documents/:id/review` (admin)
- `POST /api/car-paddy` (driver), `GET /api/car-paddy` (admin), `PATCH /api/car-paddy/:id` (admin)
- `GET /api/admin/dashboard` (admin)
- `POST /api/courier-requests` (rider), `GET /api/courier-requests/available` (driver), `PATCH /api/courier-requests/:id/accept` (driver), `PATCH /api/courier-requests/:id/status` (assigned driver or admin), `GET /api/courier-requests/:id` (party to it, or admin), `GET /api/courier-requests` (admin)
- `POST /api/emergency-alerts` (any authenticated user), `GET /api/emergency-alerts/mine` (any authenticated user), `GET /api/emergency-alerts` (admin), `PATCH /api/emergency-alerts/:id/status` (admin)
- `GET /api/subscription-plans` (any authenticated user), `POST /api/subscription-plans` (admin), `POST /api/drivers/me/subscription`, `GET /api/drivers/me/subscription`, `DELETE /api/drivers/me/subscription` (driver)
- `POST /api/trips/:id/charge` (driver on the trip, or admin) — `CARD` initializes a real Paystack transaction, `Payment` starts `PENDING`; `CASH`/`WALLET` settle immediately; `GET /api/payments/mine` (any authenticated user), `GET /api/payments` (admin), `GET /api/payments/:id/receipt` (the paying rider, or admin)
- `POST /api/billing/webhook` (Paystack calls this directly, no bearer token) — verifies the signature, re-confirms via Paystack's verify endpoint, and moves a `Payment` from `PENDING` to `SUCCEEDED`/`FAILED` on `charge.success`/`charge.failed`
- `GET /api/loyalty-tiers` (any authenticated user), `POST /api/loyalty-tiers` (admin), `GET /api/riders/me/loyalty` (rider) — current tier is *computed* from completed-trip count on every read, not stored, so it can't drift out of sync with actual trips
- `GET /api/promotions` (any authenticated user), `POST /api/promotions` (admin), `POST /api/promotions/:code/redeem` (any authenticated user, once per user — enforced by a unique constraint on `(promotionId, userId)`)
- `GET /api/pricing-rules` (any authenticated user), `POST /api/pricing-rules` (admin), `PATCH /api/pricing-rules/:id` (admin); `GET /api/surge-zones`, `POST /api/surge-zones` (admin), `PATCH /api/surge-zones/:id` (admin); `GET /api/pricing/quote?distanceKm=&durationMinutes=&zone=` (any authenticated user) — computes a fare estimate from whichever `PricingRule` is `active`, times an active `SurgeZone`'s multiplier if `zone` matches one by name
- Full interactive docs: `GET /docs` (Swagger UI), raw spec at `GET /openapi.json` — see `openapi.yaml`

Authorization is role-based via Cognito group membership (`Rider`, `Driver`,
`Admin`) checked in `src/middleware/auth.ts`. Every admin/system-wide list
endpoint above (`/drivers`, `/riders`, `/trips`, `/rentals`,
`/support-tickets`, `/car-paddy`, `/courier-requests`,
`/courier-requests/available`, `/payments`, `/emergency-alerts`) is
paginated — `?page=1&pageSize=20` (`pageSize` capped at 100), response shape
`{ data, page, pageSize, total }` (see `src/lib/pagination.ts`). Personal
`/mine` and `/me`-scoped list endpoints (naturally bounded to one user's own
data) were left as plain arrays — pagination there would add complexity
without much value.

**A routing gotcha worth knowing if you add more `/thing/:id` + `/thing/me`
pairs**: Express matches routes in registration order, and `:id` matches any
single path segment — including the literal string `me`. `GET /drivers/:id`
registered before `GET /drivers/me` will silently shadow it (every driver
calling their own profile endpoint gets the Admin-only 403 instead of their
profile) since Express never reaches the later route. Fixed here by always
registering the literal `/me` routes before the `:id` wildcard route in the
same router — `riders.routes.ts` and `drivers.routes.ts` had exactly this bug
until the test suite caught it (see `QA-01` below).

Cognito itself doesn't create a Postgres row for a new user — that's why
`POST /api/drivers/me` and `POST /api/riders/me` exist: each app calls its
own once, right after sign-up, to create the corresponding `Driver`/`User`
record (an upsert, so calling it again is harmless).

## Real-time & ride matching

`POST /api/trips` doesn't just create a trip — `src/services/matching.ts`
runs synchronously right after, looking for one `ACTIVE` driver with no
trip currently `MATCHED`/`IN_PROGRESS` and assigning them (highest-rated
first). It's deliberately not location-aware (there's no driver location
persisted in Postgres — see below), and deliberately synchronous rather
than queued; see the file's own comment for why that's the right MVP
starting point and the concrete trigger to move past it.

Live updates are a `ws` WebSocket server attached to the same HTTP server
Express listens on (`src/realtime/server.ts`, wired up in `src/index.ts`) —
not AWS AppSync. See `docs/realtime-architecture.md` for the full reasoning
and the wire protocol. In short: connect to `wss://<host>/ws?token=<Cognito
access token>`, send `{"type":"subscribe","tripId":"..."}` to join a trip's
room (rejected unless you're the rider, the assigned driver, or an Admin),
and a driver can send `{"type":"location","lat":0,"lng":0}` to broadcast
their position to everyone else subscribed to their active trip(s).
`PATCH /api/trips/:id/status` also broadcasts a `trip:status` event to the
trip's room the moment the Postgres write succeeds. Every one of these has
an HTTP equivalent (`GET /api/trips/:id/driver-location`,
`GET /api/trips/:id`) for a client that isn't holding a live connection.

Real, tested code — `src/realtime/realtime.test.ts` drives an actual `ws`
client against a real HTTP server (not a mock), covering auth rejection,
subscribe authorization, and both broadcast paths end to end.

## Payments (Paystack)

`POST /api/trips/:id/charge` with `method: "CARD"` initializes a real
Paystack transaction (`src/billing/paystack.ts`) and records a `Payment` as
`PENDING`, returning an `authorizationUrl` the mobile app opens for the
rider to complete (out of scope for this backend — the app just opens the
URL, see `user_app/lib/services/paystack_service.dart`). The actual outcome
arrives asynchronously: `POST /api/billing/webhook` verifies Paystack's
`x-paystack-signature` (HMAC-SHA512) against the *exact raw request bytes* —
which is why it's mounted in `app.ts` with `express.raw()` at that one
specific path, before the global `express.json()` — then re-confirms via
Paystack's own `GET /transaction/verify/:reference` before trusting the
event at all, and flips the matching `Payment` to `SUCCEEDED` or `FAILED` on
`charge.success`/`charge.failed`. `CASH`/`WALLET` charges skip Paystack
entirely and settle immediately, since there's no card to authorize.

Set `PAYSTACK_SECRET_KEY` to actually use this (unset is fine in dev/test —
`src/billing/paystack.ts` constructs requests with a dummy key so it never
fails to *load*, only real API calls would fail, and tests mock
`paystackClient`'s methods directly). **Not validated against a live
Paystack account** — no test-mode keys available in this sandbox — but the
webhook signature verification itself is tested for real:
`billing.routes.test.ts` builds a genuinely, correctly HMAC-SHA512-signed
payload with `signWebhookPayloadForTesting` (not a mock) and confirms the
handler updates the right `Payment`. One gotcha that cost real debugging
time while writing that test: sending the signed payload via `supertest` as
`Buffer.from(body)` silently breaks the signature check — superagent
JSON-serializes a Buffer into `{"type":"Buffer","data":[...]}` before it
hits the wire. Send the raw string instead; see the comment in
`billing.routes.test.ts`.

## Local development

```bash
cp .env.example .env      # then fill in a local Postgres URL + Cognito IDs
npm install
npm run prisma:generate
npm run dev                # ts-node-dev, hot reload on :8080
```

Run against a local Postgres with Docker:

```bash
docker run --name ravelgo-db -e POSTGRES_USER=ravelgo -e POSTGRES_PASSWORD=ravelgo \
  -e POSTGRES_DB=ravelgo -p 5432:5432 -d postgres:16
npx prisma migrate dev        # applies prisma/migrations/, already checked in
npm run prisma:seed           # populates sample rider/driver/vehicle/trip data
```

The migration in `prisma/migrations/` and the seed script have both been run
against a real local Postgres 16 instance as part of building this — not
just type-checked.

## Tests

Real, HTTP-level tests (`supertest` against the actual Express `app`, real
Postgres, not mocked) covering every route in every router — auth checks
(401/403), the happy path, and ownership/not-found edge cases:

```bash
createdb ravelgo_test        # once, or point DATABASE_URL in .env at any local test DB
npx prisma migrate deploy    # applies prisma/migrations/ to it
npm test
```

`src/middleware/auth.ts` calls a real `CognitoJwtVerifier`, and there's no
real Cognito user pool available while testing — so instead of real JWTs,
tests stub the shared `verifier.verify()` singleton with Node's built-in
`node:test` `mock.method()` (see `src/test/helpers.ts`'s `mockAuthAs()`),
which returns whatever `sub`/`cognito:groups` the test asks for.

Test files must run one at a time (`--test-concurrency=1`, already set in
the `test` script): every file shares one physical Postgres database and
resets it in its own `beforeEach`, so if Node ran files concurrently
(its default), one file's reset could wipe rows out from under a different
file's assertion mid-test — real, observed flakiness during development,
not a hypothetical.

## Building the container

```bash
docker build -t ravelgo-backend .
docker run -p 8080:8080 --env-file .env ravelgo-backend
```

This is the same image GitHub Actions builds and pushes to ECR for App
Runner to deploy — see `../infra` and `../.github/workflows`.
