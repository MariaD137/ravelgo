# RavelGo Infrastructure (AWS CDK)

Provisions everything the backend needs to run in AWS:

| Stack | What it creates |
|---|---|
| `RavelGo-Network` | VPC, isolated subnets only (no NAT gateway — kept cheap) |
| `RavelGo-Auth` | Cognito User Pool + app client + Rider/Driver/Admin groups |
| `RavelGo-Storage` | S3 buckets (driver documents, private; assets, via CloudFront) |
| `RavelGo-Data` | RDS PostgreSQL (single-AZ, `db.t4g.micro` to start) |
| `RavelGo-Api` | ECR repo + App Runner service running the backend container |
| `RavelGo-CI` | GitHub OIDC provider + IAM role GitHub Actions assumes to deploy |

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

## Adding a stage (dev/staging/prod)

Right now `bin/infra.ts` deploys one environment. To add more, either:
- Duplicate the stack instantiation block in `bin/infra.ts` with a different
  name suffix (e.g. `RavelGo-Api-Staging`) and different context values, or
- Use CDK Pipelines if you want promotion between stages automated end to
  end (a bigger step up in complexity — only worth it once you have real
  users depending on staging being separate from prod).
