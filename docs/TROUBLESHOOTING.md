# Troubleshooting & Repair Workflow

## Fixing a Bug in a Specific Component

```bash
# Start from latest develop
git checkout develop
git pull --ff-only origin develop

# Create a fix branch
git checkout -b fix/<component>-<problem>
# Example: git checkout -b fix/auth-login-timeout
```

Make your changes, then validate:

```bash
cd backend
npm run lint
npm run typecheck
npm test
npm run build
```

Commit and push:

```bash
git add <specific-files>
git commit -m "fix: resolve authentication login timeout"
git push -u origin fix/auth-login-timeout
```

Open a PR: `fix/auth-login-timeout` --> `develop`

After code review and CI passes, merge into `develop`.
When ready for production, open a PR: `develop` --> `main`.

## Emergency Production Fix (Hotfix)

```bash
# Start from production
git checkout main
git pull --ff-only origin main

# Create hotfix branch
git checkout -b hotfix/<problem>
# Example: git checkout -b hotfix/payment-failure
```

Make the smallest safe fix. Validate, commit, push:

```bash
git add <specific-files>
git commit -m "fix: resolve production payment failure"
git push -u origin hotfix/payment-failure
```

Open a PR: `hotfix/payment-failure` --> `main`

After merge and production deployment, bring the fix into develop:

```bash
git checkout develop
git pull --ff-only origin develop
git merge --no-ff hotfix/payment-failure
git push origin develop
```

If there are merge conflicts, resolve them carefully or ask for help.

## Common Issues

### Backend won't start locally

1. Check `.env` exists: `cp .env.example .env` and fill in values
2. Check Postgres is running: `docker ps`
3. Run migrations: `npx prisma migrate dev`
4. Generate Prisma client: `npm run prisma:generate`

### Tests fail in CI but pass locally

1. Check env vars: CI uses dummy values for Cognito/Stripe
2. Check Postgres: CI uses a fresh DB each run
3. Check for time-dependent tests

### Flutter app build fails

1. Run `flutter pub get`
2. Check `.env` exists: `cp .env.example .env`
3. Check Flutter SDK version: `flutter --version`
4. Clean and rebuild: `flutter clean && flutter pub get`

### Prisma migration conflicts

1. Never edit existing migration files
2. If migrations are out of sync: `npx prisma migrate dev`
3. For production issues: see docs/DATABASE.md rollback section
