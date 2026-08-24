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

## Dangerous Operations

Never run these against production without explicit approval:

- `prisma migrate reset` (drops and recreates the database)
- `prisma db push` (force-syncs schema without migrations)
- Direct `DROP TABLE` / `TRUNCATE` SQL
- Any migration that drops columns containing user data
