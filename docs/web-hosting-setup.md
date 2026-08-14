# Hosting admin_app / driver_app / user_app on the web

`infra/lib/web-stack.ts` provisions a private S3 bucket + CloudFront
distribution per Flutter app (`RavelGo-Web` stack). `.github/workflows/web-deploy.yml`
builds each app for web and syncs it to its bucket on every push to `main`
that touches that app's directory. Neither half does anything until the
one-time setup below is done.

## Prerequisites

- The `RavelGo-Web` and `RavelGo-CI` CDK stacks have been deployed (`cdk
  deploy RavelGo-Web RavelGo-CI` from `infra/`, or as part of `cdk deploy
  --all`). `RavelGo-CI` needs to be deployed *after* `RavelGo-Web` exists,
  since it grants the GitHub Actions deploy role S3/CloudFront permissions
  scoped to those specific buckets and distributions.
- The AWS CLI is configured with credentials for that account, to read the
  stack outputs below.

## 1. Read the stack outputs

```bash
aws cloudformation describe-stacks --stack-name RavelGo-Web \
  --query "Stacks[0].Outputs" --output table
```

This lists, for each app, a bucket name, a CloudFront distribution ID, and
the `https://<distribution>.cloudfront.net` URL it'll be reachable at.

## 2. Set GitHub repository variables

`web-deploy.yml` reads these by name (Settings → Secrets and variables →
Actions → Variables, not Secrets — bucket names and distribution IDs aren't
sensitive):

| Variable | Value |
|---|---|
| `ADMIN_APP_BUCKET_NAME` | `AdminAppBucketName` output |
| `ADMIN_APP_DISTRIBUTION_ID` | `AdminAppDistributionId` output |
| `DRIVER_APP_BUCKET_NAME` | `DriverAppBucketName` output |
| `DRIVER_APP_DISTRIBUTION_ID` | `DriverAppDistributionId` output |
| `USER_APP_BUCKET_NAME` | `UserAppBucketName` output |
| `USER_APP_DISTRIBUTION_ID` | `UserAppDistributionId` output |

`AWS_DEPLOY_ROLE_ARN` and `AWS_REGION` should already be set from the
backend deploy setup (`backend-deploy.yml` uses the same two) — `web-deploy.yml`
reuses the same OIDC role, just with additional S3/CloudFront permissions
added by `ci-stack.ts`.

## 3. Deploy

Push to `main` with a change under `admin_app/`, `driver_app/`, or
`user_app/` (or trigger the workflow manually) — each app builds and
deploys independently via the matrix in `web-deploy.yml`.

## Current state: mock data, no custom domain

- These apps run entirely on mock data today (see `docs/ARCHITECTURE.md`
  or its equivalent) — `web-deploy.yml` builds with `.env.example` since
  that's the only env file that exists for any of them. Real configuration
  will need a real per-environment `.env` at build time before this is
  more than a static preview of the UI.
- Each app is served at CloudFront's own `*.cloudfront.net` domain, not a
  custom domain — that needs a Route 53 hosted zone and an ACM certificate
  (in `us-east-1`, required for CloudFront) neither of which exist in this
  repo's infra yet. Follow-up work, not blocking today's deploy.

## Why the bucket names/distribution IDs are manual, not wired automatically

GitHub Actions variables can't be set directly from a CDK deploy without
either committing a GitHub token to the stack (a real secret-handling
surface to build and audit) or a custom resource calling the GitHub API
from inside CloudFormation. Reading six CFN outputs and pasting them into
repo variables once per environment is the smaller, more auditable
surface — the same tradeoff `docs/admin-bootstrap.md` makes for the first
Cognito Admin user.
