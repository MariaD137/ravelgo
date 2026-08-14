# Database

## Overview

- **Engine:** PostgreSQL 16
- **ORM:** Prisma 6.x
- **Schema:** `backend/prisma/schema.prisma`
- **Migrations:** `backend/prisma/migrations/`
- **Production host:** AWS RDS (provisioned by `infra/lib/data-stack.ts`)

## Schema Management

Prisma manages the schema as the single source of truth. To modify:

```bash
cd backend

# Edit schema.prisma, then:
npx prisma migrate dev --name descriptive_name

# This creates a migration file and applies it to the dev DB
```

## Migration Workflow

### Development

```bash
npx prisma migrate dev --name add_whatever
```

Creates a new migration SQL file and applies it locally.

### Production

```bash
npx prisma migrate deploy
```

Applies all pending migrations. Run this BEFORE deploying new application code.

### CI

The `backend-ci.yml` workflow runs `npx prisma migrate deploy` against a
disposable Postgres service container, verifying that migrations apply cleanly.

## Rollback Strategy

Prisma does not generate down migrations. For rollbacks:

1. **RDS point-in-time recovery:** Restore to a timestamp before the bad migration
2. **Manual SQL:** Write a reversal migration and apply it as a new migration
3. **Prisma db execute:** For emergency fixes:
   ```bash
   npx prisma db execute --file rollback.sql
   ```

## Backup Strategy

- **RDS automated backups:** Enabled by default, 7-day retention
- **Point-in-time recovery:** Available within the backup window
- **Manual snapshots:** Take before risky migrations

## Development Database

```bash
# Start local Postgres (Docker):
docker run -d --name ravelgo-db \
  -e POSTGRES_USER=ravelgo \
  -e POSTGRES_PASSWORD=ravelgo \
  -e POSTGRES_DB=ravelgo \
  -p 5432:5432 postgres:16

# Apply migrations:
cd backend && npx prisma migrate dev

# Seed data:
npm run prisma:seed
```

## Row-Level Security

Three tables — `DriverBankAccount`, `Payment`, `Payout` — have Postgres
row-level security enabled and **forced** (`ENABLE ROW LEVEL SECURITY` +
`FORCE ROW LEVEL SECURITY`), added in
`prisma/migrations/20260814210000_enable_rls_financial_tables`. This is a
database-level backstop behind the app-layer `requireAuth`/`requireRole` +
ownership checks on every route — not a replacement for them. If an app-layer
`where` clause is ever missing or wrong on one of these three tables, the
database itself refuses to return or write another user's row instead of
silently leaking it.

**Why FORCE, not just ENABLE:** Postgres exempts a table's owner from RLS by
default. This app uses a single Postgres role for both migrations and
runtime queries, so without FORCE, RLS would silently do nothing at all —
the owning role would bypass every policy.

**Why not just table ownership / a single connection string:** FORCE RLS
still gets bypassed unconditionally by a true Postgres superuser, regardless
of the FORCE setting — this is a hard Postgres rule, not a bug. AWS RDS's
master user is *not* a real superuser (this is deliberate on AWS's part, for
exactly this reason), so production is fine. Locally and in CI, the stock
`postgres:16` Docker image's bootstrap `POSTGRES_USER` **is** a real
superuser by default — and it can't simply be demoted:
`ALTER ROLE ravelgo NOSUPERUSER` fails with "the bootstrap user must have
the SUPERUSER attribute" (confirmed against a real run), because Postgres
specifically refuses to let the cluster's original bootstrap role ever lose
SUPERUSER, no matter who issues the ALTER ROLE — including itself.
`backend-ci.yml` instead creates a *second*, ordinary role
(`ravelgo_app`) right after migrations apply, grants it the same table
access, and points the rest of the job's queries at it via `DATABASE_URL` —
a role that never ran `CREATE TABLE` is neither the owner nor a superuser,
so RLS applies to it automatically, no FORCE or demotion needed. Do the
same locally if you want to test RLS behavior against `prisma migrate dev`
(see Development Database below) — without a second non-owner role,
`backend/src/lib/rls.test.ts`'s "a query with no session context set sees
zero rows" assertions will fail in the *other* direction (the owning
superuser sees the rows regardless of policy).

**How the app sets the session context:** see `backend/src/lib/rls.ts`.
`withUserContext(userId, fn)` runs `fn` inside a transaction with
`app.user_id` set via `set_config(..., true)` (the `true` = session-*local*,
so it never leaks across pooled connections or other requests); the
`DriverBankAccount`/`Payment`/`Payout` policies allow a row through when its
owner column matches `app.user_id`. `withBypass(fn)` sets `app.bypass =
'true'` instead, for code that's already been authorized a different way —
an Admin-gated route, the Stripe webhook (authorized by signature, not by
being a specific user), or test fixture setup. Every route touching these
three tables uses one of these two helpers; a plain `prisma.payout.findMany()`
outside of either will now always return zero rows.

**Adding RLS to another table:** write a migration enabling + forcing RLS
and a policy shaped like the three existing ones (owner-column match OR
`app.bypass = 'true'`), then convert every read/write of that table to go
through `withUserContext`/`withBypass` — including test fixtures that create
rows directly, and any `include`/join from an unprotected table into it
(Prisma's `include: { payment: true }` in `services/payouts.ts` is exactly
this case: the join still hits the RLS-protected table).

## Dangerous Operations

Never run these against production without explicit approval:

- `prisma migrate reset` (drops and recreates the database)
- `prisma db push` (force-syncs schema without migrations)
- Direct `DROP TABLE` / `TRUNCATE` SQL
- Any migration that drops columns containing user data
