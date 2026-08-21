# RavelGo AWS Staging Deployment Readiness

Verified against the actual repository — build, typecheck, migrations, and 144 tests were run live against a real Postgres 16 instance; the Docker daemon was actually started and a real `docker build` was attempted (not simulated); CDK/GitHub Actions/Cognito/S3 configuration was read from source, not from prior reports. No AWS resource was created, modified, or deployed. No credential of any kind was requested, generated, or used.

---

## Code Status

**READY.** `git status` was clean before this pass began. One functional change was made this pass (Task 2 — see below); everything else was verification/documentation. 144/144 tests pass, build and typecheck are clean, OpenAPI has exact 1:1 coverage against every registered route, and Prisma migrations apply with zero schema drift. Full detail: `PRE_AWS_STAGING_REMEDIATION.md` (the 10 P0/P1 fixes) and `FINAL_AWS_STAGING_READINESS.md` (the independent re-verification + 5 additional security fixes) from the prior two passes — both re-confirmed still true in this pass, not re-explained here.

## Docker Status

**DOCKER BUILD NOT EXECUTED (base image pull blocked by this sandbox's network policy).**

This pass got further than the prior one: the Docker daemon was actually reachable this time (`dockerd` started and `docker version`/`docker ps` succeeded against a live daemon). Running the real build —

```
cd backend && docker build -t ravelgo-backend:staging-check .
```

— failed at the very first layer, pulling the `node:22-slim` base image:

```
ERROR: failed to build: failed to solve: node:22-slim: failed to resolve source metadata
for docker.io/library/node:22-slim: ... Forbidden
```

Checking this sandbox's outbound proxy status confirmed the exact cause: `gateway answered 403 to CONNECT (policy denial or upstream failure), host: production.cloudfront.docker.com:443` — this is an explicit network-policy block on Docker Hub's image CDN in this sandbox, not a transient network error, not a Dockerfile problem, and not something to route around (retrying, switching registries, or disabling TLS verification would all violate this environment's explicit proxy policy). Reported honestly rather than worked around.

**Everything short of the actual `docker build` was independently verified**, since every command the Dockerfile runs was run directly outside Docker: `npm ci`, `npx prisma generate`, `npm run build`, and — critically — the compiled production server was booted directly (`NODE_ENV=production node dist/index.js`) and confirmed live: `GET /health` → 200, `GET /openapi.json` → 200, `GET /docs` → 200, full Helmet security header set present, CORS correctly restrictive. The Dockerfile itself was reviewed statically (unchanged from the prior pass, which added the non-root `node` user — confirmed still in place):
- Multi-stage build, `npm ci --omit=dev` in the runtime stage (production dependencies only).
- `RUN chown -R node:node /app` + `USER node` before `CMD` — container does not run as root.
- `EXPOSE 8080`, matching App Runner's configured port; `CMD ["node", "dist/index.js"]` — production start, never a dev server.
- No secrets in the image: only `package*.json`, `prisma/`, `openapi.yaml`, and compiled `dist/` are copied in (`.dockerignore` excludes `.env`/`.env.*`).
- Prisma client is generated in the runtime stage itself (`npm run prisma:generate` after the prod-only `npm ci`), so it matches what's actually in the runtime `node_modules`.

**Exact command to run on a machine with real Docker Hub access** (any laptop, CI runner, or the eventual GitHub Actions deploy job all satisfy this):

```bash
cd backend
docker build -t ravelgo-backend:staging-check .
docker run --rm -p 8080:8080 \
  -e NODE_ENV=production \
  -e DATABASE_URL=postgresql://ravelgo:ravelgo@host.docker.internal:5432/ravelgo \
  -e COGNITO_USER_POOL_ID=us-east-1_XXXXXXXXX \
  -e COGNITO_CLIENT_ID=XXXXXXXXXXXXXXXXXXXXXXXXXX \
  -e ALLOWED_ORIGINS=https://admin.ravelgo.com \
  -e STRIPE_SECRET_KEY=sk_test_XXXXXXXXXXXXXXXXXXXXXXXX \
  -e STRIPE_WEBHOOK_SECRET=whsec_XXXXXXXXXXXXXXXXXXXXXXXX \
  ravelgo-backend:staging-check
curl http://localhost:8080/health
```
(placeholder values shown — substitute a real reachable Postgres instance and your own test-mode Cognito/Stripe identifiers, never anything real for a throwaway local check).

GitHub Actions' `backend-deploy.yml` runs this exact `docker build`/`docker push` itself on every deploy (see GitHub Deployment Status below) — a real Docker Hub connection there confirms this build works, since nothing about the block encountered here is specific to the Dockerfile.

## AWS Infrastructure Status

**Nothing deployed. CDK reviewed statically — complete and internally consistent for this deployment model.** `infra/lib/` provisions, and this pass changed none of it:

| Stack | Provisions |
|---|---|
| `NetworkStack` | VPC, 2 AZs, isolated subnets only, no NAT gateway (RDS needs no outbound internet) |
| `AuthStack` | Cognito User Pool + client + `Rider`/`Driver`/`Admin` groups (see Cognito Status) |
| `StorageStack` | `documents` + `assets` S3 buckets, CloudFront distribution for `assets` |
| `DataStack` | RDS PostgreSQL 16, isolated subnet, encrypted, credentials via `Credentials.fromGeneratedSecret` |
| `ApiStack` | ECR repo, App Runner service + VPC connector to RDS, IAM roles, Stripe placeholder secret, health check on `/health` |
| `MonitoringStack` | CloudWatch alarms (5xx rate, RDS CPU, RDS free storage) + AWS Budget, all wired to an SNS email subscription |
| `CiStack` | GitHub OIDC provider + deploy role (production only — see GitHub Deployment Status) |

`infra/bin/infra.ts` supports a second, independent `--context envName=staging` environment in the same AWS account without touching the production stack names/resources — this is the natural way to stand up a staging environment from this same CDK code.

**Not deployed or verified live in this pass** — `cdk deploy` was not run, per explicit instruction (Task 13).

## Database Status

**PostgreSQL confirmed — no SQLite path exists anywhere.** `datasource db { provider = "postgresql" }` in `prisma/schema.prisma`; `grep -rni sqlite` across `backend/` and `infra/` returns nothing. `DataStack` provisions RDS PostgreSQL 16.

Migration strategy, re-confirmed this pass by actually running it against a live Postgres instance:
```bash
DATABASE_URL="<connection-string-from-DatabaseSecretArn>" npx prisma migrate deploy
```
This is the exact, documented first-deployment command (`infra/README.md`, `docs/AWS-DEPLOYMENT.md`, `docs/DEPLOYMENT-CHECKLIST.md`). **`prisma migrate reset` is never used anywhere in this codebase** — `grep -rn "migrate reset"` across the repository returns nothing. `migrate deploy` only applies pending migrations forward; it cannot wipe or reset data. Migrations are **not** run automatically at container startup (the Dockerfile's `CMD` is just `node dist/index.js`) — a container restart or App Runner auto-scaling event can never trigger a schema change on its own. Re-verified this pass: 4 migrations apply cleanly to a fresh database, `prisma migrate status` reports up to date, `prisma migrate diff` reports zero drift between the schema and migration history.

## Cognito Status

Reviewed `infra/lib/auth-stack.ts` and `docs/admin-bootstrap.md` (both pre-existing, unchanged this pass):

- **User pool**: `ravelgo-users` (or `ravelgo-users-<envName>` for a non-production environment), email sign-in, email auto-verification, standard password policy (8+ chars, upper/lower/digit required).
- **Client**: one shared `MobileClient` (no secret — public client, correct for mobile apps), 1-hour access tokens, 30-day refresh tokens, used by all three Flutter apps.
- **Groups**: `Rider`, `Driver`, `Admin` — created by the stack itself, checked via the `cognito:groups` claim by `requireRole()` in `backend/src/middleware/auth.ts`.
- **Signup behavior**: `selfSignUpEnabled: true`. A newly self-signed-up user is in **no** group until someone puts them there — by design, not a defect (the app UI never offers an Admin signup path, and even Rider/Driver group assignment isn't automatic on signup in the current CDK).
- **Role assignment process**: manual, via `aws cognito-idp admin-add-user-to-group`.

**Manual first-Admin bootstrap — exact steps** (already fully documented in `docs/admin-bootstrap.md`, summarized here, **not performed in this pass** — no AWS credentials were available or requested):
```bash
aws cognito-idp admin-create-user --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example \
  --user-attributes Name=email,Value=admin@ravelgo.example Name=email_verified,Value=true \
    Name=given_name,Value=Admin Name=family_name,Value=User \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example --password '<a-strong-temporary-password>' --permanent

aws cognito-idp admin-add-user-to-group --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example --group-name Admin
```
This has **not been completed** — it requires a deployed `AuthStack` and real AWS CLI credentials, neither available to this session.

## S3/CloudFront Status

Reviewed `infra/lib/storage-stack.ts` and `backend/src/routes/uploads.routes.ts` fresh this pass:

- **Documents bucket**: `blockPublicAccess: BLOCK_ALL`, SSE-S3 encryption, `enforceSSL: true`, versioned. Only reachable via short-lived (300s) presigned URLs generated by the backend.
- **Assets bucket**: also `blockPublicAccess: BLOCK_ALL` at the bucket level — public reachability is only through the CloudFront distribution, via Origin Access Control (not a public bucket policy).
- **Upload restrictions — confirmed intact, not undone**: `POST /uploads/presign`'s `contentType` is restricted to a per-bucket allowlist (`application/pdf`/`image/jpeg`/`image/png`/`image/webp` for `documents`; image types only for `assets`), and `fileName` is capped at 200 characters and restricted to a safe character set (`/^[\w.\- ]{1,200}$/`) — this is the stored-XSS-via-asset-upload fix from the prior pass, verified still present and its 7 regression tests still passing.
- **Object ownership**: every presigned key is prefixed with the caller's own Cognito sub (`${req.user!.sub}/${randomUUID()}-${fileName}`) — one user cannot write into another's key prefix via this endpoint.
- **Presigned URLs**: 300-second expiry, scoped to a single `PutObjectCommand` for a specific bucket+key+content-type.

## Stripe Status

**CODE READY** for what exists; **DASHBOARD CONFIGURATION REQUIRED** before any of it can run against a real Stripe account:

| Capability | Status |
|---|---|
| PaymentIntent creation (`POST /trips/:id/charge`) | **CODE READY** — amount always comes from server-side `trip.finalFare`, never the request body (adversarially verified — a client-injected `amount` field is silently ignored) |
| Webhook signature verification | **CODE READY** — raw body handling correct, verified with real signed test events |
| Webhook replay/out-of-order protection | **CODE READY** — added last pass, atomic conditional update, re-verified this pass still passing |
| Stripe Connect (driver payouts) | **NOT IMPLEMENTED** — `services/payouts.ts`'s `processPayout` still simulates success; not faked as complete |
| Refunds | **NOT IMPLEMENTED** — no refund endpoint, no `stripe.refunds.create` call anywhere in the codebase; `PaymentStatus.REFUNDED` exists as a schema value nothing ever sets |
| Driver subscription billing | **NOT IMPLEMENTED** — subscribing sets internal DB state only; no Stripe `Subscription`/`Invoice` object is ever created, no money is collected |

**Exact Stripe Dashboard actions required for staging** (none performed by this session — no Stripe credentials were requested or used):
1. In Stripe's test mode, copy the test-mode secret key (`sk_test_...`).
2. Create a webhook endpoint pointing at `https://<your-app-runner-url>/api/billing/webhook` (the URL only exists after `ApiStack` is deployed).
3. Subscribe that webhook to at least `payment_intent.succeeded` and `payment_intent.payment_failed` (the only two event types this codebase currently handles).
4. Copy the webhook's signing secret (`whsec_...`).
5. Overwrite the CDK-provisioned placeholder secret with both values:
   ```bash
   aws secretsmanager put-secret-value --secret-id <StripeSecretArn output from ApiStack> \
     --secret-string '{"secretKey":"sk_test_...","webhookSecret":"whsec_..."}'
   ```
Use **test-mode** keys for staging — never live keys. No values for any of the above were requested from, generated by, or provided to this session.

## Secrets Required

Variable **names** only — no values requested, generated, or provided by this session:

```
DATABASE_URL          (dev only — App Runner assembles this from DB_HOST/DB_PORT/DB_NAME/DB_USERNAME/DB_PASSWORD instead)
DB_HOST
DB_PORT
DB_NAME
DB_USERNAME
DB_PASSWORD
COGNITO_USER_POOL_ID
COGNITO_CLIENT_ID
AWS_REGION
DOCUMENTS_BUCKET
ASSETS_BUCKET
ALLOWED_ORIGINS
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
```

All of these come from CDK stack outputs or Secrets Manager at deploy/runtime (see `infra/lib/api-stack.ts`'s `runtimeEnvironmentVariables`/`runtimeEnvironmentSecrets`) — none are hardcoded, none are committed, none appear in `openapi.yaml`, Docker image, or any documentation file with a real value (only placeholder patterns like `sk_test_XXXXXXXXXXXXXXXXXXXXXXXX` in `.env.example`). `backend/src/config/env.ts` throws at container boot — refusing to start — if `ALLOWED_ORIGINS`, `STRIPE_SECRET_KEY`, or `STRIPE_WEBHOOK_SECRET` are missing when `NODE_ENV=production`: **fails closed**, not open. The one env-var fallback in application code (`billing/stripe.ts`'s `env.STRIPE_SECRET_KEY ?? "sk_test_dummy_for_local_dev_and_tests"`) was specifically re-checked against this requirement: it is provably unreachable in production, since `config/env.ts`'s boot-time check already throws before this line could ever execute with an unset key — confirmed correct, left as-is (it is the intended dev/test convenience, not a live fail-open path). No password, encryption key, or webhook signing secret anywhere in this codebase has a predictable or insecure default.

## GitHub Deployment Status

**Ready — uses GitHub OIDC, no static AWS keys.** `.github/workflows/backend-deploy.yml`, re-read fresh this pass:
```yaml
permissions:
  id-token: write   # assumes the AWS role via OIDC — no stored AWS keys
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
```
`AWS_DEPLOY_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY_URI`, `APP_RUNNER_SERVICE_ARN` are GitHub Actions **repository variables** (`vars.*`), not secrets — none of them are sensitive (they're ARNs/URIs, not credentials). `infra/lib/ci-stack.ts` provisions the matching IAM OIDC provider + deploy role, scoped to `repo:<org>/<repo>:ref:refs/heads/<branch>` — only that exact repo+branch can assume it. This workflow triggers on push to `main` only; it will not run on this session's working branch. No long-lived AWS access key is used or needed anywhere in this deployment path — exactly the model requested.

## Tests

**144/144 passing**, 0 failing, 0 skipped. Run with `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` explicitly unset to match real CI (which has none) — clean, ~117s. Includes 2 new tests added this pass (Task 2's PricingRule seed — see below).

## Build

**PASS** — `npm run build` (`tsc -p tsconfig.json`), zero errors.

## Typecheck

**PASS** — `npx tsc --noEmit`, zero errors.

## OpenAPI

**PASS** — parses, 63 paths, exact 1:1 coverage against every registered Express route (scripted cross-check, both directions).

## Prisma/Migrations

**PASS** — 4 migrations apply cleanly to a fresh Postgres 16 database; `migrate status` reports up to date; `migrate diff` reports zero drift; no destructive migration anywhere in the migration history or startup path.

## Security

**PASS** — nothing new found this pass beyond the two prior passes' findings, all already fixed and re-confirmed intact (upload content-type/filename restrictions, webhook replay/ordering protection, non-root Docker user, malformed-request handling, trip-status IDOR, driver payout ownership, suspended-user enforcement, matching race conditions). No new code paths were introduced this pass except the pricing seed, which was reviewed for the same class of issues and found clean (idempotent, no destructive behavior, no hardcoded route-level pricing).

---

## Task 2 — PricingRule Seed (this pass's code change)

**Problem:** the fare-validation engine (`GET /pricing/quote`, `POST /trips`) is fully implemented and correct, but has nothing to validate against in a freshly-deployed, unseeded database — `estimatedFare` at trip creation is accepted from the client as-is until an active `PricingRule` exists.

**What was checked first:** the repository does not define any real RavelGo business fare structure anywhere — not in code, not in docs, not in prior audit reports. The only pricing-shaped numbers in the repo are arbitrary test fixtures (e.g. `baseFare: 2, perKm: 1, perMinute: 0.2` in `pricing.routes.test.ts`) and one flavor-text demo trip amount in the existing seed script. Per this task's own instruction not to invent production business pricing, **no real fare structure is invented here.**

**What was done instead — extending the existing seed mechanism** (`backend/prisma/seed.ts`, already wired via `npm run prisma:seed` / `npx prisma db seed`, unchanged mechanism, no new script created):
```ts
const existingActiveRule = await prisma.pricingRule.findFirst({ where: { active: true } });
if (!existingActiveRule) {
  await prisma.pricingRule.upsert({
    where: { name: "Staging Default (PLACEHOLDER — replace before production)" },
    update: {},
    create: { name: "...", baseFare: 2.0, perKm: 1.0, perMinute: 0.25, active: true },
  });
}
```
- Uses the existing `PricingRule` Prisma model — no schema change.
- **Idempotent**: re-running the seed after the rule already exists just logs and skips; verified live by running `npm run prisma:seed` twice in a row against a real database (second run: `"An active PricingRule already exists ... — skipping placeholder seed."`).
- **Never creates a duplicate active rule**: only acts when zero active rules exist at all — if an admin has since configured real pricing (or any other active rule exists for any reason), re-running the seed is a guaranteed no-op and never touches it.
- **No destructive behavior**: no `deleteMany`, no reset, consistent with the rest of `seed.ts`, which has never contained one.
- **Not hardcoded into route handlers**: the seed only writes a database row; `POST /trips` and `GET /pricing/quote` are unchanged and still read whichever `PricingRule` is `active` from the database, exactly as before.

**⚠️ Explicitly flagged, not silently invented as real pricing:** `baseFare=2.00`, `perKm=1.00`, `perMinute=0.25` (USD) are plain, round, obviously-placeholder numbers chosen only to make the pricing engine functional in a fresh environment — named `"Staging Default (PLACEHOLDER — replace before production)"` specifically so it cannot be mistaken for a real rate card. **The value that must be supplied manually:** RavelGo's actual fare structure (base fare, per-km rate, per-minute rate, and any market-specific variants) is a business decision this session cannot and does not make. Before any production launch, an authorized person must either `PATCH /api/pricing-rules/:id` this placeholder or create and activate a new `PricingRule` with real, business-approved numbers.

**Verified end-to-end**, live, against a real database: ran the seed script (confirmed idempotent on a second run), then confirmed via direct query that the pricing engine's own formula computes correctly from the seeded row. Two new permanent regression tests were added (`pricing.routes.test.ts`) mirroring the exact seeded values and proving both `GET /api/pricing/quote` and `POST /api/trips` compute a correct, server-authoritative fare from them — both pass.

---

## Remaining Blockers

| Item | Classification |
|---|---|
| Run `docker build` for real (blocked by this sandbox's network policy, not the Dockerfile) | **BLOCKER** (for *this session*; not a blocker for staging — GitHub Actions' own deploy job runs this exact build with real Docker Hub access) |
| Replace the placeholder `PricingRule` with real business fare values | **MANUAL BOOTSTRAP** — a business decision, not an engineering one |
| `cdk deploy --all` (or `--context envName=staging`) | **AWS CONFIGURATION** |
| First `npx prisma migrate deploy` against the deployed RDS instance | **AWS CONFIGURATION** |
| Bootstrap the first Cognito Admin user | **MANUAL BOOTSTRAP** |
| Replace the Stripe placeholder secret with real test-mode Dashboard values | **STRIPE CONFIGURATION** |
| Register the Stripe webhook endpoint | **STRIPE CONFIGURATION** |
| Stripe Connect (driver payouts) | **DEFERRED** — explicitly out of scope until requested |
| Refunds | **DEFERRED** — doesn't exist, would be new feature work |
| Real Stripe billing for driver subscriptions | **DEFERRED** — doesn't exist, would be new feature work |
| Tiered/per-endpoint rate limiting | **POST-STAGING** |
| Request-ID/correlation-ID logging | **POST-STAGING** |
| 10 pre-existing `@typescript-eslint/no-explicit-any` lint errors | **POST-STAGING** — confirmed to predate all three remediation passes |
| 5 `npm audit` advisories, all devDependency tooling only | **POST-STAGING** |

---

## Exact Deployment Sequence

Written assuming nothing has been deployed yet.

1. **Get AWS CLI + CDK working locally** (or in a CI job) with real credentials for the target AWS account — this session never had or needed any. `npm install -g aws-cdk` if not already available; `cd infra && npm ci`.

2. **First-time CDK bootstrap** (once per AWS account+region, if not already done):
   ```bash
   cdk bootstrap aws://<ACCOUNT_ID>/<REGION>
   ```

3. **Deploy the infrastructure:**
   ```bash
   cd infra
   cdk deploy --all \
     --context alertEmail=you@example.com \
     --context monthlyBudgetUsd=150 \
     --context allowedOrigins="https://admin.ravelgo.com"
   ```
   For a separate staging environment alongside an eventual production one: add `--context envName=staging`.

4. **Note the CDK outputs** — you'll need `UserPoolId`, `UserPoolClientId`, `DatabaseSecretArn`, `DocumentsBucketName`, `AssetsBucketName`, `StripeSecretArn`, `EcrRepositoryUri`, `ServiceUrl`, `GitHubActionsDeployRoleArn`.

5. **Run the first database migration** (one time, from a machine with the RDS connection string — the isolated subnet means this generally has to be run from inside the VPC, e.g. an ECS one-off task or an EC2 bastion, or temporarily via a tool that can reach the private subnet):
   ```bash
   DATABASE_URL="<connection-string-built-from-DatabaseSecretArn>" npx prisma migrate deploy
   ```

6. **Seed the placeholder pricing rule** (and, optionally, the demo rider/driver/vehicle data) the same way — from a machine that can reach the database:
   ```bash
   DATABASE_URL="<same-connection-string>" npm run prisma:seed
   ```
   Then, as soon as the real fare structure is decided, replace it via an Admin token against `PATCH /api/pricing-rules/:id`.

7. **Bootstrap the first Cognito Admin** — see Cognito Status above for the exact three `aws cognito-idp` commands.

8. **Configure GitHub Actions**: set repository **variables** (not secrets — they're not sensitive) `AWS_DEPLOY_ROLE_ARN` (from step 4's `GitHubActionsDeployRoleArn` output), `AWS_REGION`, `ECR_REPOSITORY_URI`, `APP_RUNNER_SERVICE_ARN`.

9. **Push to `main`** (or manually run the `Backend Deploy` workflow) — GitHub Actions builds the Docker image, pushes it to ECR, and triggers an App Runner deployment, all via OIDC, no AWS keys ever touch GitHub.

10. **Configure Stripe** (test mode) — see Stripe Status above for the exact 5 steps, ending with overwriting the placeholder secret.

11. **Smoke test**: `curl https://<ServiceUrl>/health` should return `{"status":"ok","database":"connected",...}`. Check `GET /openapi.json` and `/docs` load. Sign up a test Rider and Driver through the (not-yet-connected) mobile apps or directly via Cognito, exercise one full trip lifecycle (create → match → complete → charge) using the real Stripe test-mode flow, and confirm the CloudWatch alarms/App Runner logs show activity as expected.

Only after all of the above has been done and observed working should staging be considered **AWS STAGING ACTUALLY DEPLOYED AND VERIFIED** — that statement has not been made anywhere in this report because none of it has happened yet in this session. What this report does say, and can say with confidence: **CODE READY FOR AWS STAGING.**
