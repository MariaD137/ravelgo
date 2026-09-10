# RavelGo Infrastructure (AWS CDK)

Provisions everything the backend needs to run in AWS:

| Stack | What it creates |
|---|---|
| `RavelGo-Network` | VPC, isolated subnets only (no NAT gateway — kept cheap) |
| `RavelGo-Auth` | Cognito User Pool + app client + Rider/Driver/Admin groups |
| `RavelGo-Storage` | S3 buckets (driver documents, private; assets, via CloudFront) |
| `RavelGo-Data` | RDS PostgreSQL (single-AZ, `db.t4g.micro` to start) |
| `RavelGo-Api` | ECR repo + App Runner service running the backend container |
| `RavelGo-Monitoring` | CloudWatch alarms (5xx rate, RDS CPU/storage) + AWS Budget, both -> one SNS topic -> email |
| `RavelGo-CI` / `RavelGo-CI-staging` | GitHub OIDC provider (created once, by the production stack) + one IAM role per environment that GitHub Actions assumes to deploy (see "Staging" below) |

Validated locally with `cdk synth` (no AWS credentials needed for that). Actually
deploying (`cdk deploy`) does need your own AWS credentials — nobody's AWS
account is wired into this repo.

## One-time setup

1. **Install the AWS CLI** and run `aws configure` with your own AWS account's
   credentials (or `aws sso login` if you use IAM Identity Center).
2. **Bootstrap CDK** in your account/region (one-time per account+region):
   ```bash
   cd infra
   npm install
   npx cdk bootstrap aws://<your-account-id>/<your-region>
   ```
3. **Deploy everything**:
   ```bash
   npx cdk deploy --all
   # Or, if the admin dashboard's real domain isn't https://admin.ravelgo.com:
   npx cdk deploy --all --context allowedOrigins="https://your-real-domain.com"
   ```
   This takes ~15-20 minutes the first time (mostly the RDS instance). Note
   the outputs at the end — you'll need `EcrRepositoryUri`, `ServiceUrl`,
   `UserPoolId`, `UserPoolClientId`, `StripeSecretArn`, and
   `GitHubActionsDeployRoleArn`.

3a. **Replace the placeholder Stripe secret.** `RavelGo-Api` creates a
    Secrets Manager secret with dummy `sk_live_REPLACE_ME` /
    `whsec_REPLACE_ME` values (App Runner needs *something* to reference at
    deploy time, and CDK can't know your real Stripe keys) — overwrite it
    once with the real ones from your Stripe dashboard:
    ```bash
    aws secretsmanager put-secret-value --secret-id <StripeSecretArn output> \
      --secret-string '{"secretKey":"sk_live_...","webhookSecret":"whsec_..."}'
    ```
    Same "one manual step, documented" pattern as bootstrapping the first
    Cognito Admin user — see `../docs/admin-bootstrap.md`.

4. **Push a first image** so the App Runner service has something to run
   (`cdk deploy` creates the service, but it needs at least one image in ECR
   before it's healthy):
   ```bash
   cd ../backend
   aws ecr get-login-password --region <your-region> | \
     docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
   docker build -t ravelgo-backend .
   docker tag ravelgo-backend:latest <EcrRepositoryUri>:latest
   docker push <EcrRepositoryUri>:latest
   ```
   After this, every push to `main` (once the GitHub Actions workflow is
   wired up — see `../.github/workflows/backend-deploy.yml`) rebuilds and
   redeploys automatically; App Runner watches the `:latest` tag.

5. **Wire up GitHub Actions** with the deploy role from step 3 — add these as
   **repository variables** (not secrets, they aren't sensitive) in
   GitHub → Settings → Secrets and variables → Actions → Variables:
   - `AWS_REGION` — e.g. `us-east-1`
   - `AWS_DEPLOY_ROLE_ARN` — the `GitHubActionsDeployRoleArn` output
   - `ECR_REPOSITORY_URI` — the `EcrRepositoryUri` output
   - `APP_RUNNER_SERVICE_ARN` — find via `aws apprunner list-services`

   No AWS access keys are ever stored in GitHub — the workflow authenticates
   via OIDC (see `RavelGo-CI` stack).

6. **Run the first database migration**:
   ```bash
   cd ../backend
   DATABASE_URL="<connection-string-from-DatabaseSecretArn>" npx prisma migrate deploy
   ```
   (Pull the connection details from Secrets Manager, or run this from
   somewhere with network access to the VPC — a bastion host or `aws ssm
   start-session` port-forward, since the DB has no public endpoint.)

## Cost notes

This is deliberately the cheapest *correct* setup, not the cheapest possible
one:
- No NAT gateway (App Runner reaches RDS via VPC Connector instead) saves
  ~$32/month over a typical NAT setup.
- `db.t4g.micro` single-AZ Postgres is the smallest reasonable production
  instance — expect a low double-digit dollar amount per month. Move to
  Multi-AZ or Aurora Serverless v2 once uptime/traffic justify the cost.
- App Runner bills per vCPU/memory-second while running, plus a small
  provisioned amount while idle — cheaper than an always-on ECS/EKS cluster
  for an app that isn't yet at scale.

## Adding a stage (staging/dev/etc)

Both production and non-production environments live in the same AWS account/region.
Production is the default; to deploy a staging environment:

```bash
cd infra
# Deploy all stacks with staging suffix
npx cdk deploy --all --context envName=staging
# Or with custom alert email and budget:
npx cdk deploy --all --context envName=staging --context alertEmail=staging-alerts@example.com --context monthlyBudgetUsd=50
```

This creates separate, parallel resources:
- Stack names get suffixed: `RavelGo-Network-staging`, `RavelGo-Auth-staging`, etc.
- ECR repo becomes `ravelgo-backend-staging` (not `ravelgo-backend`)
- App Runner service becomes `ravelgo-backend-staging`
- Cognito User Pool name becomes `ravelgo-users-staging`
- All other resource names are automatically suffixed

### Deploying staging via GitHub Actions (manual trigger)

`.github/workflows/staging-deploy.yml` builds and pushes the backend image,
restarts the App Runner service, and publishes all three Flutter web apps —
but only when you trigger it yourself (GitHub → Actions →
"Deploy to Staging" → "Run workflow"). It deliberately does **not** run on
every push to `main`, so an ordinary merge never kicks off an AWS deployment
on its own. AWS only allows one GitHub OIDC provider per issuer per account,
so staging's `CiStack` imports the same provider production's created rather
than making a second one (see `infra/lib/ci-stack.ts`) — no manual OIDC setup
needed beyond what step 5 above already did for production.

One-time setup:

1. Deploy staging's CI role (after `npx cdk deploy --all --context envName=staging` has run at least once):
   ```bash
   cd infra
   npm run bootstrap-ci-staging
   ```
   Note the `GitHubActionsDeployRoleArn` output.
2. Add these as **repository (or "staging" environment) variables** in
   GitHub → Settings → Secrets and variables → Actions:
   - `AWS_REGION` — e.g. `us-east-1` (shared with production's workflow if already set)
   - `AWS_STAGING_DEPLOY_ROLE_ARN` — the role ARN from step 1
3. Optional: add a `GOOGLE_MAPS_API_KEY` **secret** so the deployed web apps render maps.

Database migrations are **not** part of this automation — the database has no
public endpoint, so applying one requires the separate, deliberately manual
`bash scripts/migrate-staging.sh` (see its own comments, and
`scripts/migrate-env.sh`, for why this stays a human step rather than
something the CI role can trigger unattended). The workflow's
`check-migrations` job just warns, non-blockingly, when the commit you're
deploying adds a new migration you haven't applied yet.

For production, `.github/workflows/backend-deploy.yml` runs automatically on
every push to `main` that touches `backend/**` — unlike staging's manual
`workflow_dispatch`, there is no deliberate trigger to pair with a migration
step. It carries the same non-blocking `check-migrations` warning staging
does, and the matching manual step is `bash scripts/migrate-production.sh`
(asks for an explicit typed confirmation before touching the live database).
Its web app isn't auto-deployed yet — extending this workflow to publish the
three Flutter web builds the way staging's does is a reasonable next step
once production has its own web-app hosting story.
