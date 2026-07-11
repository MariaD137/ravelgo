# RavelGo Backend

Unified REST API for the rider, driver, and admin apps. Node.js + Express +
TypeScript, PostgreSQL via Prisma, authenticated with Amazon Cognito JWTs.

## Endpoints (MVP slice)

- `GET /health` — unauthenticated health check (used by App Runner)
- `POST /api/trips`, `GET /api/trips/:id`, `PATCH /api/trips/:id/status`, `GET /api/trips` (admin)
- `GET /api/drivers` (admin), `GET /api/drivers/:id` (admin), `PATCH /api/drivers/:id/status` (admin), `GET /api/drivers/me` (driver)
- `GET /api/documents/me`, `POST /api/documents` (driver), `PATCH /api/documents/:id/review` (admin)
- `POST /api/car-paddy` (driver), `GET /api/car-paddy` (admin), `PATCH /api/car-paddy/:id` (admin)
- `GET /api/admin/dashboard` (admin)

Authorization is role-based via Cognito group membership (`Rider`, `Driver`,
`Admin`) checked in `src/middleware/auth.ts`. This is a starting slice, not
full coverage of every screen in the three Flutter apps — extend the
`routes/` folder the same way as traffic/features are wired up.

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
npx prisma migrate dev --name init
```

## Building the container

```bash
docker build -t ravelgo-backend .
docker run -p 8080:8080 --env-file .env ravelgo-backend
```

This is the same image GitHub Actions builds and pushes to ECR for App
Runner to deploy — see `../infra` and `../.github/workflows`.
