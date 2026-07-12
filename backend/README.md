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

Authorization is role-based via Cognito group membership (`Rider`, `Driver`,
`Admin`) checked in `src/middleware/auth.ts`. This still isn't full coverage
of every screen in the three Flutter apps (couriers, fraud/emergency alerts,
subscriptions, loyalty, and pricing/surge have no backing model yet) —
extend the `routes/` folder the same way as traffic/features are wired up.

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

## Building the container

```bash
docker build -t ravelgo-backend .
docker run -p 8080:8080 --env-file .env ravelgo-backend
```

This is the same image GitHub Actions builds and pushes to ECR for App
Runner to deploy — see `../infra` and `../.github/workflows`.
