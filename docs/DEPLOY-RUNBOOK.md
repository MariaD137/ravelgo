# RavelGo — AWS Deployment Runbook (current)

This is the authoritative, step-by-step runbook for a **first-time production
deploy** of the current codebase (post P0 launch-readiness work). It is tailored
to this repo's actual CDK wiring and supersedes the older, more generic
`AWS-DEPLOYMENT.md` / `DEPLOYMENT-QUICKSTART.md` where they differ.

> **Who runs this:** a person (or CI) holding **real AWS credentials with admin
> rights** for the target account. `aws sts get-caller-identity` must succeed.
> The Claude Code sandbox cannot run these steps — it has no AWS access.

Stacks created (production names; a non-prod env appends `-<envName>`):
`RavelGo-Network`, `RavelGo-Auth`, `RavelGo-Storage`, `RavelGo-Data`,
`RavelGo-Api`, `RavelGo-Monitoring`, `RavelGo-CI`.

---

## Quick start — pull from GitHub and deploy in AWS CloudShell

CloudShell already has your credentials, the AWS CLI, Node, git **and Docker**
(Docker is available in 13 Regions — incl. `us-east-1`, `us-east-2`, `us-west-2`,
`eu-west-1`, `eu-central-1`, `ap-southeast-1/2`, `ap-northeast-1`), so the whole
deploy — image build included — can run there.

### First: authenticate to GitHub (the repo is private)

A bare `git clone` fails with `remote: invalid credentials` — CloudShell has your
*AWS* credentials, not your GitHub ones. Set up a **read-only deploy key** once
(it persists in CloudShell's home directory, per Region):

```bash
# Clear any stale credential that may be cached from an earlier attempt
git config --global --unset-all credential.helper 2>/dev/null || true
rm -f ~/.git-credentials

ssh-keygen -t ed25519 -f ~/.ssh/ravelgo_deploy -N "" -C "cloudshell-ravelgo"
cat ~/.ssh/ravelgo_deploy.pub
```

Add that public key at **Settings → Deploy keys → Add deploy key**
(<https://github.com/MariaD137/ravelgo/settings/keys>). Leave *Allow write
access* **unchecked** — the deploy only needs to read. Then:

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  IdentityFile ~/.ssh/ravelgo_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config
ssh -T git@github.com    # expect: "Hi MariaD137/ravelgo! You've successfully authenticated"
```

<details>
<summary>Alternative: a fine-grained personal access token</summary>

Create one at <https://github.com/settings/personal-access-tokens/new> scoped to
this repository only, with **Contents: Read-only**. Then clone with it and
immediately scrub it from `.git/config`:

```bash
read -rsp "GitHub PAT: " GH_TOKEN; echo      # read -s keeps it out of history
git clone --branch main \
  "https://x-access-token:${GH_TOKEN}@github.com/MariaD137/ravelgo.git"
cd ravelgo && git remote set-url origin https://github.com/MariaD137/ravelgo.git
unset GH_TOKEN
```
</details>

### Then: deploy

```bash
# Work under /tmp: CloudShell's home directory is capped at 1 GB and
# node_modules for CDK + backend will blow past it.
cd /tmp && rm -rf ravelgo
git clone --branch main git@github.com:MariaD137/ravelgo.git
cd ravelgo

# --- configure this deploy ---------------------------------------------------
export AWS_REGION=us-east-1
export ENVNAME=production
export ALLOWED_ORIGINS="https://app.yourdomain.com,https://admin.yourdomain.com"
export SES_FROM_EMAIL="no-reply@yourdomain.com"   # must be SES-verified
export ALERT_EMAIL="ops@yourdomain.com"

# --- run the phases, checking output between each ----------------------------
bash scripts/cloudshell-deploy.sh preflight
bash scripts/cloudshell-deploy.sh infra-base   # ~15 min (RDS is the slow part)
bash scripts/cloudshell-deploy.sh secrets      # prompts for Paystack + Maps keys
bash scripts/cloudshell-deploy.sh image        # docker build + push to ECR
bash scripts/cloudshell-deploy.sh service      # App Runner comes up
bash scripts/cloudshell-deploy.sh outputs      # everything you need afterwards
```

Then apply migrations from a CloudShell **VPC environment** (step 6 — the DB is
private and unreachable from a normal shell):

```bash
cd /tmp && git clone git@github.com:MariaD137/ravelgo.git && cd ravelgo
bash scripts/cloudshell-migrate.sh
```

(A VPC environment is a separate CloudShell environment with its **own** home
directory, so repeat the deploy-key setup above there — or use the PAT method.)

If a CloudShell session times out mid-deploy, just re-clone and re-run the
phase — CloudFormation holds the state, so the phases are idempotent.

The sections below explain what each phase does and how to do it by hand.

---

## 0. Prerequisites

- AWS account with billing enabled; admin credentials configured
  (`aws configure`; verify `aws sts get-caller-identity`).
- Node.js 22 and npm.
- Docker running locally (needed to build the backend image).
- A real Paystack secret key: `sk_live_…` (or `sk_test_…`). Paystack signs
  webhooks with this same key — no separate webhook secret to obtain.
- A Google Maps **server** API key (for the backend Places/Geocoding proxy).
- For email (P0 #13): a domain or address you can verify in SES, and — for real
  delivery beyond the SES sandbox — SES production access (request early; it can
  take ~24h).
- Pick a region (examples below use `us-east-1`) and note your **account ID**.

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

---

## 1. Bootstrap CDK (once per account/region)

```bash
cd infra
npm ci
npx cdk bootstrap aws://$ACCOUNT_ID/$AWS_REGION
npx cdk synth   # sanity: templates generate with no error
```

---

## 2. Phase-1 deploy — everything except the App Runner service

The App Runner service can't start until an image exists in ECR, and the ECR
repo is created by this stack. So the **first** deploy uses
`-c deployService=false`: it stands up the VPC, RDS, Cognito, S3/CloudFront,
ECR repo, Secrets Manager placeholders, and IAM — but **not** the App Runner
service.

```bash
npx cdk deploy --all \
  -c deployService=false \
  -c sesFromEmail="no-reply@yourdomain.com" \
  -c allowedOrigins="https://app.yourdomain.com,https://admin.yourdomain.com" \
  -c alertEmail="ops@yourdomain.com"
```

- RDS takes **10–15 min** — normal.
- Approve the IAM/security-group change sets when prompted.
- **Save these CDK outputs** (also in the CloudFormation console):
  `EcrRepositoryUri`, `DatabaseSecretArn`, `PaystackSecretArn`, `MapsSecretArn`,
  `UserPoolId`, `UserPoolClientId`, `GitHubActionsDeployRoleArn`,
  `AssetsDistributionDomain`, `AlertTopicArn`. (`ServiceUrl` appears after
  phase 2.)

Capture the ones you'll reuse:

```bash
export ECR_URI=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" --output text)
export DB_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" --output text)
export PAYSTACK_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='PaystackSecretArn'].OutputValue" --output text)
export MAPS_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='MapsSecretArn'].OutputValue" --output text)
```

---

## 3. Overwrite the placeholder secrets

The stack lays down placeholders (`sk_live_REPLACE_ME`, etc.) so nothing real is
committed. Overwrite them **before** the service serves traffic:

```bash
aws secretsmanager put-secret-value --secret-id "$PAYSTACK_SECRET_ARN" \
  --secret-string '{"secretKey":"sk_live_xxx"}'

aws secretsmanager put-secret-value --secret-id "$MAPS_SECRET_ARN" \
  --secret-string '{"serverKey":"AIza_your_server_key"}'
```

---

## 4. Build and push the backend image to ECR

```bash
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ECR_URI%/*}"

cd ../backend
docker build -t "$ECR_URI:latest" -t "$ECR_URI:$(git rev-parse --short HEAD)" .
docker push "$ECR_URI:latest"
docker push "$ECR_URI:$(git rev-parse --short HEAD)"
```

> The Dockerfile pulls its base image from ECR Public and installs OpenSSL for
> Prisma — no changes needed. (The image was build-validated during
> development.)

---

## 5. Phase-2 deploy — bring up the App Runner service

Re-run the deploy **without** `deployService=false` (it defaults to true). Keep
the same `sesFromEmail` / `allowedOrigins` / `alertEmail` context values.

```bash
cd ../infra
npx cdk deploy RavelGo-Api \
  -c sesFromEmail="no-reply@yourdomain.com" \
  -c allowedOrigins="https://app.yourdomain.com,https://admin.yourdomain.com" \
  -c alertEmail="ops@yourdomain.com"

export SERVICE_URL=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='ServiceUrl'].OutputValue" --output text)
echo "$SERVICE_URL"
```

The service will start but **the database has no tables yet** — do step 6 before
expecting real requests to work.

---

## 6. Run database migrations against the (isolated) RDS

> **Important — the older docs gloss over this.** RDS is deployed in
> `PRIVATE_ISOLATED` subnets: it has **no public endpoint and no route from your
> laptop**. `npx prisma migrate deploy` with the secret's host will simply time
> out from outside the VPC. You must reach it from inside the VPC.

**Recommended: `scripts/migrate-env.sh`, from an ordinary CloudShell.** It needs
no bastion and no VPC CloudShell environment: it packages `backend/`, creates a
CodeBuild project placed *inside* the VPC (egress subnets, the same security
group App Runner uses, which RDS already allows on 5432), reads the DB
credentials from Secrets Manager at run time, runs `prisma migrate deploy`, and
tails the build log back to your terminal.

```bash
git clone https://github.com/MariaD137/ravelgo.git && cd ravelgo
bash scripts/migrate-staging.sh        # or: bash scripts/migrate-production.sh
```

Production prompts for confirmation before it touches the live database. Both
are safe to re-run: `migrate deploy` only applies migrations not yet applied.
Success ends with *"All migrations have been successfully applied."*

**Fallback: a CloudShell VPC environment** (only if CodeBuild is unavailable to
you).

1. CloudShell console → **Actions → Create VPC environment**:
   - **VPC:** the RavelGo VPC
   - **Subnet:** one of the **egress** subnets (`PRIVATE_WITH_EGRESS`). It has
     NAT, so npm/git/AWS APIs still work, *and* it routes to the isolated DB
     subnets. Do **not** pick a public subnet — VPC environments in public
     subnets get no internet.
   - **Security group:** any SG in the VPC; note its id.
2. Allow that SG into the database (temporarily):

   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id <RDS_SECURITY_GROUP_ID> --protocol tcp --port 5432 \
     --source-group <CLOUDSHELL_SG_ID>
   ```

3. In the VPC environment, clone and run the helper — it reads the DB secret,
   checks reachability, and applies the chain with `sslmode=require`:

   ```bash
   git clone https://github.com/MariaD137/ravelgo.git && cd ravelgo
   bash scripts/cloudshell-migrate.sh
   ```

4. **Remove** the temporary ingress rule when finished
   (`aws ec2 revoke-security-group-ingress …`).

> Note: only **two** VPC environments are allowed per IAM principal, and RDS
> forces SSL (`rds.force_ssl=1`), which is why the URL carries `sslmode=require`.

**Migrations are a deliberate manual step, and deploying does not run them.**
The deploy workflows only print a `::warning::` when the commit adds migration
files; nothing blocks. So a deploy can succeed while the database is still on
the old schema, and every endpoint that reads a missing column then answers 500.
Run the migration for any deploy that adds one, and confirm with
`/health/schema` (§7) before calling the deploy done.

Do **not** run `prisma:seed` in production — the seed guard refuses production
anyway (P0 #14).

---

## 7. Verify

```bash
curl -fsS "$SERVICE_URL/health"        # expect HTTP 200
curl -fsS "$SERVICE_URL/health/schema" # expect HTTP 200 {"status":"ok"}
```

`/health/schema` compares the migrations the running image ships against the
`_prisma_migrations` rows in the database it is pointed at. A 503 means the two
have drifted and names exactly what is missing:

```json
{ "status": "out-of-date", "expected": 37, "applied": 35,
  "pending": ["zz09_driver_last_location", "zz10_referrals"], "failed": [],
  "remedy": "Run scripts/migrate-<env>.sh against this environment." }
```

`pending` is "shipped but never run" — go back to §6. `failed` is "started and
did not finish, or was rolled back"; `migrate deploy` refuses to continue past
one of those, so resolve it before re-running. The post-deploy smoke test
(`scripts/ci/backend-smoke.sh`) probes this endpoint, so a deploy over an
unmigrated database goes red here rather than reporting green.

- App Runner service shows **RUNNING** (App Runner console).
- Cognito user pool exists with `Rider` / `Driver` / `Admin` groups (auto-created
  by the Auth stack).
- CloudWatch alarms present; confirm the SNS email subscription (check inbox for
  the AWS confirmation).
- RDS is **Available**; `\dt` through the tunnel lists 41 tables incl. `Payout`
  with the `Payout_driverId_period_key` unique index and RESTRICT FKs.

---

## 8. Create the first admin (and any seed drivers)

New sign-ups are auto-added to `Rider`. Elevate a real user once they've signed
up in the app:

```bash
ENVNAME=production bash scripts/set-role.sh you@yourdomain.com Admin
# they must sign out and back in for the new group to take effect
```

(Drivers normally self-onboard in-app via the server-authoritative
`POST /drivers/apply`, P0 #2, then an admin approves them to ACTIVE.)

---

## 9. Enable CI/CD for future backend deploys (required for production auto-deploy)

The `backend-deploy.yml` workflow auto-builds and ships the image on pushes to
`main`. Its `preflight` job now **fails the run with an explicit error**
(instead of silently skipping) when the required repository variables are
missing, so a push to `main` can no longer look "deployed" while production
never actually changed. Set:

- GitHub → **Settings → Secrets and variables → Actions → Variables**, add:
  - `AWS_DEPLOY_ROLE_ARN` = `GitHubActionsDeployRoleArn` output (redeploy the
    `RavelGo-CI` stack first — `cd infra && npm run bootstrap-ci` — so the
    role also has `apprunner:ListOperations`, used to confirm the rollout
    actually succeeded)
  - `AWS_REGION` = your region

  `ECR_REPOSITORY_URI` and `APP_RUNNER_SERVICE_ARN` are optional: the
  workflow now discovers the `ravelgo-backend` repository/service by name
  automatically. Set them only to override that lookup.

After that, merging backend changes into `main` deploys the image, waits for
the App Runner rollout to actually finish (`scripts/ci/apprunner-wait.sh` —
catches a failed/rolled-back deploy that used to still show green), and
smoke-tests `/health` and `/health/pricing` on the live service
(`scripts/ci/backend-smoke.sh`). (Infra changes still deploy via
`cdk deploy`; there is intentionally no auto-`cdk deploy` pipeline.)

The three Flutter web apps deploy separately and manually, from the Actions
tab: **Deploy Web Apps to Production** (`production-web-deploy.yml`), the
same role/variables, builds against the live production API/Cognito config
and publishes to the production CloudFront distribution.

---

## 10. SES production access (P0 #13)

`-c sesFromEmail=…` switches Cognito to send via SES (verify with the
`EmailSender` output = SES developer/production, not `COGNITO_DEFAULT`). To send
to arbitrary recipients you must:

1. Verify the sender identity (domain or address) in SES.
2. Request **production access** (move out of the SES sandbox) in the SES
   console. Until then, SES only delivers to verified addresses.

---

## 11. Mobile / web apps

For each Flutter app (`user_app`, `driver_app`, `admin_app`), create its `.env`
from `.env.example` and set:

- `API_BASE_URL` = the `ServiceUrl` (or your custom domain in front of it)
- `COGNITO_USER_POOL_ID` = `UserPoolId` output
- `COGNITO_CLIENT_ID` = `UserPoolClientId` output
- `AWS_REGION`, `GOOGLE_MAPS_API_KEY` (browser key), currency vars
- No Paystack key belongs in any app's `.env` — the backend holds the
  Paystack secret key and returns a one-time checkout URL for card
  payments/top-ups; see `user_app/lib/services/paystack_service.dart`.

Then build (`flutter pub get && flutter build …`). **These app builds were
not run in the dev environment (no Flutter SDK), so build and smoke-test
each app against staging before release.**

---

## 12. Rollback & teardown

- **Bad image:** push a known-good tag and `aws apprunner start-deployment`, or
  roll the App Runner service back to a previous deployment in the console.
- **Bad infra change:** `cdk deploy` the previous revision, or roll back the
  stack in CloudFormation.
- **Full teardown (non-prod):** `npx cdk destroy --all -c envName=<env>`. RDS
  has deletion protection / retention on production — expect to remove that
  guard deliberately. This deletes real data; don't do it to production
  casually.

Cost note: RDS + App Runner + NAT run ~continuously. See `infra/README.md` for
the estimate; tear down non-prod environments when idle.

---

## 13. Troubleshooting — an app screen shows a 500

A screen reading *"RavelGo had a server problem loading …(500)"*, or the
backend's own *"Database schema is out of date on this server (pending
migrations not applied)"*, is almost always schema drift: a deploy shipped code
that reads a column the database does not have yet, because §6 was skipped.

Check the environment first — it answers without credentials and names the
cause:

```bash
curl -s "$SERVICE_URL/health/schema" | jq .
```

- **503 with a non-empty `pending`** → run §6 against that environment. That is
  the whole fix; no code change is involved.
- **503 with a non-empty `failed`** → a migration started and never finished, or
  was rolled back. `migrate deploy` will not continue past it; resolve that
  migration before re-running.
- **200 `{"status":"ok"}`** → the schema is current and the 500 is something
  else. Read the App Runner logs for the failing request.

Two things worth knowing when you are reading this from a user's screenshot:

- **Any endpoint touching the affected table fails, not only the obvious one.**
  `zz09_driver_last_location` adds `Driver.lastLat/lastLng/lastLocationAt`;
  Prisma selects every scalar on a model, so an unmigrated database breaks
  `GET /drivers/me` (the driver app's "Couldn't load your account status") *and*
  `GET /api/rentals` (the rider's Rent a Car screen), which read `Driver` only
  incidentally. The screen you are looking at may not be the feature the
  migration was for.
- **The web apps must be redeployed to show the real message.** Since the apps
  learned to surface the backend's own explanation on a 5xx, an out-of-date
  schema reads as *"Database schema is out of date on this server"* rather than
  a bare `(500)`. A bundle published before that change still shows the generic
  text, so a stale CloudFront build hides the very clue you need. Redeploy the
  web apps ("Deploy Web Apps to Production", or the staging deploy workflow) —
  they publish to S3 and invalidate CloudFront.
