# Deployment

## Architecture

```
feature/* or fix/*
    |
    v
Pull Request --> CI (lint, typecheck, test, build)
    |
    v
  develop (integration branch)
    |
    v
Pull Request --> CI
    |
    v
  main (production)
    |
    v
  backend-deploy.yml --> ECR --> App Runner
```

## Current Production Deployment

**Provider:** AWS App Runner
**Trigger:** Push to `main` branch (backend files changed)
**Workflow:** `.github/workflows/backend-deploy.yml`

### What happens on merge to main

1. GitHub Actions checks out the code
2. Authenticates to AWS via OIDC (no long-lived keys)
3. Builds the Docker image from `backend/Dockerfile`
4. Pushes to Amazon ECR with commit SHA tag + `latest`
5. Triggers App Runner redeployment

### Required GitHub Environment Variables (production)

| Variable | Description |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC deploy |
| `AWS_REGION` | AWS region (e.g., `us-east-1`) |
| `ECR_REPOSITORY_URI` | ECR repository URI |
| `APP_RUNNER_SERVICE_ARN` | App Runner service ARN |

These are configured in GitHub Settings > Environments > production.

## Backend Build

```bash
cd backend
npm ci
npm run prisma:generate
npm run build
```

Output: `backend/dist/`

## Backend Start

```bash
cd backend
node dist/index.js
```

Requires environment variables from `.env.example`.

## Database Migrations

```bash
cd backend
npx prisma migrate deploy
```

Run migrations BEFORE deploying new application code.

## Rollback

### Application rollback

App Runner maintains previous image versions. To roll back:

1. In AWS Console > App Runner > Service > Deployments
2. Or redeploy a previous ECR image tag:
   ```
   aws apprunner start-deployment --service-arn <ARN>
   ```

### Database rollback

Prisma does not have built-in down migrations. Options:
- Restore from RDS point-in-time backup
- Write and apply a manual reversal migration

## Flutter Apps

Not yet deployed to app stores. When ready:
- Build with `flutter build apk` / `flutter build ios`
- Distribute via Google Play Console and App Store Connect

## Staging Environment

No staging environment currently exists. Recommended setup:
- Duplicate the CDK stacks with a `staging` environment prefix
- Deploy `develop` branch pushes to staging App Runner
- Use a separate RDS instance and S3 buckets
- Use Stripe test mode keys
