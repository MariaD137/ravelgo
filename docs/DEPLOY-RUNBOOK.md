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

## 0. Prerequisites

- AWS account with billing enabled; admin credentials configured
  (`aws configure`; verify `aws sts get-caller-identity`).
- Node.js 22 and npm.
- Docker running locally (needed to build the backend image).
- Real Stripe keys: `sk_live_…` (or `sk_test_…`) and the webhook signing
  secret `whsec_…`.
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
  `EcrRepositoryUri`, `DatabaseSecretArn`, `StripeSecretArn`, `MapsSecretArn`,
  `UserPoolId`, `UserPoolClientId`, `GitHubActionsDeployRoleArn`,
  `AssetsDistributionDomain`, `AlertTopicArn`. (`ServiceUrl` appears after
  phase 2.)

Capture the ones you'll reuse:

```bash
export ECR_URI=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" --output text)
export DB_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" --output text)
export STRIPE_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='StripeSecretArn'].OutputValue" --output text)
export MAPS_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name RavelGo-Api \
  --query "Stacks[0].Outputs[?OutputKey=='MapsSecretArn'].OutputValue" --output text)
```

---

## 3. Overwrite the placeholder secrets

The stack lays down placeholders (`sk_live_REPLACE_ME`, etc.) so nothing real is
committed. Overwrite them **before** the service serves traffic:

```bash
aws secretsmanager put-secret-value --secret-id "$STRIPE_SECRET_ARN" \
  --secret-string '{"secretKey":"sk_live_xxx","webhookSecret":"whsec_xxx"}'

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

**Recommended: a throwaway SSM bastion + port-forward.**

1. Launch a tiny Amazon Linux 2023 instance in one of the VPC's **egress**
   subnets (it needs the SSM agent, which that AMI ships, and outbound 443 for
   SSM — the egress subnet provides it), with an instance profile that has
   `AmazonSSMManagedInstanceCore`.
2. Allow the bastion's security group inbound to the RDS security group on 5432
   (add a temporary ingress rule; remove it when done).
3. Read the DB connection parts from the secret:

   ```bash
   aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" \
     --query SecretString --output text
   # -> { "host": "...rds.amazonaws.com", "port":5432, "username":"...",
   #      "password":"...", "dbname":"ravelgo" }
   ```

4. Port-forward RDS to your machine through the bastion via SSM:

   ```bash
   aws ssm start-session --target <bastion-instance-id> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters '{"host":["<rds-host>"],"portNumber":["5432"],"localPortNumber":["5432"]}'
   ```

5. In another shell, run the migration chain against the tunnel. Use
   `sslmode=require` (RDS forces SSL):

   ```bash
   cd backend
   export DATABASE_URL="postgresql://<user>:<pass>@127.0.0.1:5432/ravelgo?sslmode=require"
   npx prisma migrate deploy
   ```

   Success: *"All migrations have been successfully applied."* (13 migrations —
   the chain was fresh-DB validated during development.)

6. **Tear down** the temporary ingress rule and the bastion instance.

Do **not** run `prisma:seed` in production — the seed guard refuses production
anyway (P0 #14).

> **Recommended follow-up (not required for this deploy):** add a VPC-internal
> migration runner (a CodeBuild project in the egress subnet, or a one-shot task)
> so future migrations don't need a manual bastion. Tracked as a P1 infra
> improvement.

---

## 7. Verify

```bash
curl -fsS "$SERVICE_URL/health"        # expect HTTP 200
```

- App Runner service shows **RUNNING** (App Runner console).
- Cognito user pool exists with `Rider` / `Driver` / `Admin` groups (auto-created
  by the Auth stack).
- CloudWatch alarms present; confirm the SNS email subscription (check inbox for
  the AWS confirmation).
- RDS is **Available**; `\dt` through the tunnel lists ~26 tables incl. `Payout`
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

## 9. Enable CI/CD for future backend deploys (optional but recommended)

The `backend-deploy.yml` workflow auto-builds and ships the image on pushes to
`main`, but only once the OIDC role and repo variables exist. The role ARN is a
CDK output:

- GitHub → **Settings → Secrets and variables → Actions → Variables**, add:
  - `AWS_DEPLOY_ROLE_ARN` = `GitHubActionsDeployRoleArn` output
  - `AWS_REGION` = your region
  - `ECR_REPOSITORY_URI` = `EcrRepositoryUri` output
  - `APP_RUNNER_SERVICE_ARN` = the App Runner service ARN (App Runner console)

After that, merging backend changes into `main` deploys the image and triggers
`aws apprunner start-deployment`. (Infra changes still deploy via `cdk deploy`;
there is intentionally no auto-`cdk deploy` pipeline.)

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
- `user_app` only: `STRIPE_PUBLISHABLE_KEY` = your `pk_live_…`/`pk_test_…`
  (**publishable** key only — never the secret)

Then build (`flutter pub get && flutter build …`). `flutter_stripe` needs its
native setup (Android `minSdk 21`, iOS deployment target) per the Stripe SDK
docs. **These app builds were not run in the dev environment (no Flutter SDK),
so build and smoke-test each app against staging before release.**

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
