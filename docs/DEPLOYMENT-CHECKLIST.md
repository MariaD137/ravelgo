# RavelGo Deployment Checklist

Quick reference for deploying to AWS. Use this alongside `AWS-DEPLOYMENT.md` for detailed instructions.

---

## Pre-Deployment (15 minutes)

- [ ] AWS Account created and billing enabled
- [ ] AWS CLI installed: `aws --version` ✓
- [ ] AWS CLI configured: `aws configure` ✓
- [ ] AWS credentials verified: `aws sts get-caller-identity` ✓
- [ ] **Account ID saved** for later use
- [ ] Node.js 18+: `node --version` ✓
- [ ] Docker installed: `docker --version` ✓
- [ ] Paystack account created
- [ ] Paystack secret key obtained (`sk_live_*`)

---

## CDK Bootstrap (5 minutes)

```bash
cd infra
npm install
```

- [ ] Dependencies installed
- [ ] Bootstrap CDK: `npx cdk bootstrap aws://<ACCOUNT_ID>/<REGION>`
- [ ] Bootstrap successful (S3 bucket created in AWS)

---

## Validation (2 minutes)

```bash
npx cdk synth --all
```

- [ ] No compilation errors
- [ ] CloudFormation templates generated

---

## Infrastructure Deployment (25-30 minutes)

```bash
npx cdk deploy --all
```

**Watch the timeline:**
- [ ] VPC/networking created (1-2 min)
- [ ] Cognito/S3/ECR created (3-5 min)
- [ ] **RDS PostgreSQL created** (⏳ 10-15 min — this is normal and slow)
- [ ] App Runner created (1-2 min)
- [ ] Monitoring stack created (1-2 min)
- [ ] GitHub OIDC created (1-2 min)

**Save all CDK outputs:**
- [ ] `ServiceUrl` - App Runner endpoint
- [ ] `EcrRepositoryUri` - Docker image repository
- [ ] `PaystackSecretArn` - Secrets Manager secret ARN
- [ ] `UserPoolId` - Cognito user pool ID
- [ ] `UserPoolClientId` - Cognito app client ID
- [ ] `GitHubActionsDeployRoleArn` - GitHub Actions IAM role
- [ ] `AlertTopicArn` - SNS topic for alerts

---

## Post-Deployment Configuration (5 minutes)

### Update Paystack Secret

```bash
aws secretsmanager put-secret-value \
  --secret-id <PaystackSecretArn> \
  --secret-string '{"secretKey":"sk_live_xxx"}'
```

- [ ] Real Paystack key updated (not `REPLACE_ME`)
- [ ] Verified: `aws secretsmanager get-secret-value --secret-id <PaystackSecretArn>`

---

## Backend Deployment (5 minutes)

### Login to ECR

```bash
aws ecr get-login-password --region <REGION> | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
```

- [ ] Logged in to ECR

### Build & Push Image

```bash
cd backend
docker build -t ravelgo-backend:latest .
docker tag ravelgo-backend:latest <EcrRepositoryUri>:latest
docker push <EcrRepositoryUri>:latest
```

- [ ] Image built successfully
- [ ] Image pushed to ECR
- [ ] App Runner detects new image (check AWS Console)
- [ ] App Runner service becomes RUNNING (⏳ 3-5 min)

---

## Database Setup (3 minutes)

### Run Migrations

```bash
export DATABASE_URL="postgres://username:password@host:5432/ravelgo"
cd backend
DATABASE_URL="$DATABASE_URL" npx prisma migrate deploy
```

- [ ] Database connection string obtained from Secrets Manager
- [ ] Migrations ran successfully
- [ ] Tables created: `users`, `trips`, `payments`, etc.

---

## Verification (5 minutes)

### Backend Health

```bash
curl https://<ServiceUrl>/health
```

- [ ] Returns: `{"status":"ok"}`
- [ ] HTTP 200 status

### App Runner Status

```bash
aws apprunner describe-service --service-arn <SERVICE_ARN> --query 'Service.Status'
```

- [ ] Status is `RUNNING`

### Cognito

```bash
aws cognito-idp describe-user-pool --user-pool-id <UserPoolId>
```

- [ ] User pool exists and is active

### RDS

```bash
psql postgres://user:pass@host:5432/ravelgo -c "\dt"
```

- [ ] All Prisma tables exist

---

## GitHub Actions Setup (Optional, 5 minutes)

### Add Repository Variables

In GitHub → Settings → Secrets and variables → Actions → Variables:

- [ ] `AWS_REGION` = `us-east-1` (your region)
- [ ] `AWS_DEPLOY_ROLE_ARN` = `arn:aws:iam::...` (from outputs)
- [ ] `ECR_REPOSITORY_URI` = `123456789012.dkr.ecr...` (from outputs)
- [ ] `APP_RUNNER_SERVICE_ARN` = `arn:aws:apprunner:...` (get from AWS CLI)

### Test Deployment

```bash
echo "# Test" >> README.md
git add README.md && git commit -m "Test CI/CD" && git push origin main
```

- [ ] GitHub Actions workflow triggered
- [ ] Workflow completes successfully (⏳ ~10 min)
- [ ] App Runner detects new image
- [ ] Backend comes back online

---

## Monitoring Setup (2 minutes)

### Email Alerts

- [ ] Check email for SNS subscription confirmations (from CloudWatch)
- [ ] Click "Confirm subscription" in each email
- [ ] Alerts now enabled for:
  - App Runner 5xx errors (>10 in 5 min)
  - RDS CPU (>80% for 15 min)
  - RDS storage (<2 GiB)
  - Budget (80% and 100% of monthly limit)

---

## Final Verification Checklist

- [ ] All 7 stacks deployed (Network, Auth, Storage, Data, Api, Monitoring, CI)
- [ ] Paystack secret updated with a real key
- [ ] Docker image in ECR and running
- [ ] Database migrations completed
- [ ] Health check returns 200 OK
- [ ] Cognito pool created
- [ ] CloudWatch alarms configured
- [ ] (Optional) GitHub Actions deployed
- [ ] (Optional) Email alerts confirmed

---

## Deployment Summary

| Step | Time | Status |
|------|------|--------|
| Pre-deployment checks | 15 min | ☐ |
| CDK bootstrap | 5 min | ☐ |
| Infrastructure deploy | 25-30 min | ☐ |
| Paystack config | 2 min | ☐ |
| Backend image push | 5 min | ☐ |
| Database setup | 3 min | ☐ |
| Verification | 5 min | ☐ |
| GitHub Actions (opt) | 5 min | ☐ |
| Monitoring setup | 2 min | ☐ |
| **Total** | **~65-75 min** | |

---

## Quick Reference: Common Commands

```bash
# Check deployment status
aws cloudformation describe-stacks --query 'Stacks[0].StackStatus'

# View App Runner service
aws apprunner describe-service --service-arn <ARN>

# View RDS status
aws rds describe-db-instances --db-instance-identifier ravelgo-db

# View ECR images
aws ecr describe-images --repository-name ravelgo-backend

# Check Cognito user pool
aws cognito-idp describe-user-pool --user-pool-id <ID>

# View CloudWatch alarms
aws cloudwatch describe-alarms

# Stream App Runner logs
aws logs tail /aws/apprunner/ravelgo-backend/default_platform --follow

# Destroy everything (⚠️ WARNING: deletes all data)
cd infra && npx cdk destroy --all
```

---

## Troubleshooting Quick Links

See full troubleshooting guide in `AWS-DEPLOYMENT.md`:
- Role does not exist
- RDS taking too long
- App Runner not healthy
- Database migration failed
- Health check returns 502
- GitHub Actions fails

---

**Ready? Start with the Pre-Deployment section!**
