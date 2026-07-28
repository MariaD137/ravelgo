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
- `POST /api/trips`, `GET /api/trips/:id`, `PATCH /api/trips/:id/status`, `GET /api/trips` (admin)
- `GET /api/documents/me`, `POST /api/documents` (driver), `PATCH /api/documents/:id/review` (admin)
- `POST /api/car-paddy` (driver), `GET /api/car-paddy` (admin), `PATCH /api/car-paddy/:id` (admin)
- `GET /api/admin/dashboard` (admin)
- `POST /api/courier-requests` (rider), `GET /api/courier-requests/available` (driver), `PATCH /api/courier-requests/:id/accept` (driver), `PATCH /api/courier-requests/:id/status` (assigned driver or admin), `GET /api/courier-requests/:id` (party to it, or admin), `GET /api/courier-requests` (admin)
- `POST /api/emergency-alerts` (any authenticated user), `GET /api/emergency-alerts/mine` (any authenticated user), `GET /api/emergency-alerts` (admin), `PATCH /api/emergency-alerts/:id/status` (admin)
- `GET /api/subscription-plans` (any authenticated user), `POST /api/subscription-plans` (admin), `POST /api/drivers/me/subscription`, `GET /api/drivers/me/subscription`, `DELETE /api/drivers/me/subscription` (driver)
- `POST /api/trips/:id/charge` (driver on the trip, or admin) — records a `Payment` for a `COMPLETED` trip's `finalFare`; `GET /api/payments/mine` (any authenticated user), `GET /api/payments` (admin)

Authorization is role-based via Cognito group membership (`Rider`, `Driver`,
`Admin`) checked in `src/middleware/auth.ts`. Still open: loyalty tiers,
promotions, pricing rules/surge zones, pagination on list endpoints, and an
OpenAPI/Swagger spec — extend the `routes/` folder and `prisma/schema.prisma`
the same way as traffic/features are wired up.

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

Real-time ride matching/tracking (driver location, live trip updates) is
intentionally out of scope for this skeleton — add a WebSocket API or AWS
AppSync subscription layer when you get there.

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
