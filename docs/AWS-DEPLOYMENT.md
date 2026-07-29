# RavelGo AWS Deployment Guide

Complete walkthrough for deploying RavelGo to AWS for the first time.

**Estimated time:** 30-45 minutes (mostly waiting for RDS to spin up)
**Estimated cost:** $50-100/month for MVP setup

---

## Prerequisites

Before starting, you'll need:

1. **AWS Account** with billing enabled
2. **AWS CLI** installed and configured
   ```bash
   # Install
   brew install awscli  # macOS
   # or download from https://aws.amazon.com/cli/
   
   # Configure with your credentials
   aws configure
   # Enter: Access Key ID, Secret Access Key, region (e.g., us-east-1), output format (json)
   ```

3. **Node.js 18+** (for CDK)
   ```bash
   node --version  # Should be v18.0.0 or higher
   ```

4. **Docker** installed (for building backend image)
   ```bash
   docker --version
   ```

5. **Stripe Account** with API keys
   - Sign up at https://stripe.com
   - Get `sk_live_...` (secret key) and `whsec_...` (webhook secret)

6. **GitHub Personal Access Token** (for OIDC setup)
   - Create at https://github.com/settings/tokens
   - Keep it handy (you won't need it for this deployment, but good to have)

---

## Step 1: Verify AWS Access

```bash
aws sts get-caller-identity
```

Should output:
```json
{
  "UserId": "AIDAI...",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:root"
}
```

**Your Account ID is `123456789012` (save this for later)**

---

## Step 2: Bootstrap CDK

This one-time step prepares your AWS account for CDK deployments.

```bash
cd infra
npm install

# Bootstrap for your region (e.g., us-east-1)
export AWS_REGION=us-east-1
npx cdk bootstrap aws://<your-account-id>/$AWS_REGION
# Example: npx cdk bootstrap aws://123456789012/us-east-1
```

**Wait for:**
```
✓ Environment aws://123456789012/us-east-1 bootstrapped.
```

This creates an S3 bucket and IAM roles CDK needs.

---

## Step 3: Validate CDK Synth

Before deploying, validate that the CDK code compiles without errors.

```bash
npx cdk synth --all
```

Should output:
```
✓ Successfully synthesized to cdk.out/
```

If you see errors, check:
- `infra/bin/infra.ts` syntax
- All imported stack files exist
- Node.js version is compatible

---

## Step 4: Deploy Infrastructure to AWS

This deploys all 7 stacks. **RDS takes ~15 minutes.**

```bash
# Deploy all stacks
npx cdk deploy --all

# Or deploy one at a time (useful if deployment stalls):
npx cdk deploy RavelGo-Network
npx cdk deploy RavelGo-Auth
npx cdk deploy RavelGo-Storage
npx cdk deploy RavelGo-Data
npx cdk deploy RavelGo-Api
npx cdk deploy RavelGo-Monitoring
npx cdk deploy RavelGo-CI
```

When prompted, type `y` to confirm each deployment.

**Watch for CloudFormation events. Typical timeline:**
- 1-2 min: VPC, subnets, security groups
- 3-5 min: Cognito, S3, ECR repo
- 10-15 min: **RDS PostgreSQL creation** (this is slow, normal)
- 1-2 min: App Runner, monitoring alarms
- 1-2 min: GitHub Actions OIDC provider

**At the end, CDK outputs:**
```
Outputs:
RavelGo-Api.ServiceUrl = https://xxxxx.awsapprunner.com
RavelGo-Api.EcrRepositoryUri = 123456789012.dkr.ecr.us-east-1.amazonaws.com/ravelgo-backend
RavelGo-Api.StripeSecretArn = arn:aws:secretsmanager:us-east-1:123456789012:secret:ravelgo-stripe-xxx
RavelGo-Auth.UserPoolId = us-east-1_xxxxxxxxx
RavelGo-Auth.UserPoolClientId = 1234567890abcdefghijklmnop
RavelGo-Monitoring.AlertTopicArn = arn:aws:sns:us-east-1:123456789012:ravelgo-alerts
RavelGo-CI.GitHubActionsDeployRoleArn = arn:aws:iam::123456789012:role/ravelgo-github-deploy-role
```

**Save these outputs.** You'll need them for the next steps.

---

## Step 5: Update Stripe Secret

Replace the placeholder Stripe keys with your real ones.

```bash
# From the outputs above, use the StripeSecretArn
aws secretsmanager put-secret-value \
  --secret-id arn:aws:secretsmanager:us-east-1:123456789012:secret:ravelgo-stripe-xxx \
  --secret-string '{"secretKey":"sk_live_your_real_key_here","webhookSecret":"whsec_your_real_key_here"}'
```

**Verify it worked:**
```bash
aws secretsmanager get-secret-value --secret-id arn:aws:secretsmanager:us-east-1:123456789012:secret:ravelgo-stripe-xxx
```

Should show your real keys (not `REPLACE_ME`).

---

## Step 6: Push First Backend Image to ECR

App Runner needs at least one Docker image in ECR to become healthy.

```bash
# Get login credentials for ECR
export AWS_REGION=us-east-1
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.$AWS_REGION.amazonaws.com

# From outputs above, use EcrRepositoryUri
export ECR_URI=123456789012.dkr.ecr.us-east-1.amazonaws.com/ravelgo-backend

# Build backend image
cd ../backend
docker build -t ravelgo-backend:latest .

# Tag for ECR
docker tag ravelgo-backend:latest $ECR_URI:latest

# Push to ECR
docker push $ECR_URI:latest
```

**Watch for:**
```
✓ Pushed to $ECR_URI:latest
```

App Runner will detect the new image and start a deployment (takes ~3-5 min).

---

## Step 7: Run Database Migrations

Create tables and seed initial data.

```bash
# Get the database connection string from Secrets Manager
export DB_SECRET_ARN="arn:aws:secretsmanager:us-east-1:123456789012:secret:ravelgo-database-xxx"

# Retrieve credentials
aws secretsmanager get-secret-value --secret-id $DB_SECRET_ARN --query 'SecretString' --output text | jq .

# Build connection string from output:
# Example: postgres://postgres:password@ravelgo-db.xxxxx.us-east-1.rds.amazonaws.com:5432/ravelgo

export DATABASE_URL="postgres://username:password@host:5432/ravelgo"

# Run migrations
cd backend
DATABASE_URL="$DATABASE_URL" npx prisma migrate deploy
```

If you get a connection error, the DB might still be starting. Wait 2-3 minutes and retry.

**Success looks like:**
```
✓ Ran 1 migration
✓ Database is in sync with schema
```

---

## Step 8: Verify Deployment

### Check App Runner Service

```bash
aws apprunner describe-service --service-arn arn:aws:apprunner:us-east-1:123456789012:service/ravelgo-backend/xxxxx --query 'Service.Status'
```

Should output: `"RUNNING"`

### Check Service is Healthy

```bash
# Get the service URL from CDK outputs
curl https://xxxxx.awsapprunner.com/health
```

Should output:
```json
{"status":"ok"}
```

### Check Database

```bash
# Connect to RDS and verify tables
psql postgres://username:password@host:5432/ravelgo -c "\dt"
```

Should list Prisma tables: `users`, `trips`, `payments`, etc.

### Check Cognito

```bash
aws cognito-idp describe-user-pool --user-pool-id us-east-1_xxxxxxxxx --query 'UserPool.Name'
```

Should output: `ravelgo-users`

---

## Step 9: Setup GitHub Actions (Optional but Recommended)

Wire up automatic backend deployments on every push to `main`.

### Add Repository Variables

In your GitHub repo → Settings → Secrets and variables → Actions → Variables, add:

| Variable | Value | Source |
|----------|-------|--------|
| `AWS_REGION` | `us-east-1` | Your region |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::...` | CDK output: `GitHubActionsDeployRoleArn` |
| `ECR_REPOSITORY_URI` | `123456789012.dkr.ecr.us-east-1...` | CDK output: `EcrRepositoryUri` |
| `APP_RUNNER_SERVICE_ARN` | `arn:aws:apprunner:us-east-1:...` | Get from `aws apprunner list-services` |

### Find App Runner Service ARN

```bash
aws apprunner list-services --region us-east-1 --query 'ServiceSummaryList[0].ServiceArn'
```

### Push to Trigger CI/CD

```bash
# Make a dummy change to trigger GitHub Actions
echo "# Deployment test" >> README.md
git add README.md
git commit -m "Trigger CI/CD test"
git push origin main
```

Watch the deployment on GitHub → Actions tab. Should complete in ~10 minutes.

---

## Step 10: Setup Monitoring Alerts (Recommended)

Confirm email subscriptions for CloudWatch alerts.

1. Check your email for AWS SNS subscription confirmation (from CloudWatch alerts)
2. Click "Confirm subscription"
3. You'll now receive alerts if:
   - Backend returns 10+ errors in 5 minutes
   - RDS CPU exceeds 80%
   - RDS storage drops below 2 GiB
   - Monthly spend exceeds 80% of budget

---

## Verification Checklist

- [ ] AWS CLI configured and `aws sts get-caller-identity` works
- [ ] CDK bootstrap completed
- [ ] `npx cdk synth --all` succeeds
- [ ] `npx cdk deploy --all` completes (outputs saved)
- [ ] Stripe secret updated with real keys
- [ ] Backend Docker image pushed to ECR
- [ ] Database migrations ran successfully
- [ ] `curl https://xxxxx.awsapprunner.com/health` returns 200
- [ ] Cognito User Pool created
- [ ] CloudWatch alarms configured
- [ ] GitHub Actions variables added (optional)
- [ ] Email alert subscriptions confirmed (optional)

---

## Cost Breakdown (Monthly Estimate)

| Service | Tier | Cost |
|---------|------|------|
| RDS PostgreSQL | `db.t4g.micro`, single-AZ | $10-15 |
| App Runner | 1 vCPU, 2 GB RAM, idle | $8-12 |
| ECR | <1 GB images | <$1 |
| S3 (documents + assets) | <10 GB | $1-2 |
| CloudFront (asset CDN) | <100 GB transfer | $2-5 |
| CloudWatch | Alarms + logs | $3-5 |
| Cognito | <50k MAU | Free tier |
| Secrets Manager | 1 secret | $0.40 |
| **Total** | | **$25-40** |

(Budget alert set to $100/month to catch unexpected spikes)

---

## Troubleshooting

### "Deployment failed: Role does not exist"
**Cause:** Bootstrap wasn't run properly.
**Fix:** Re-run `npx cdk bootstrap` and wait 1 minute.

### "RDS is still being created" (after 20 min)
**Cause:** Normal for first RDS instance. AWS is provisioning hardware.
**Fix:** Wait another 5-10 minutes. Check CloudFormation events in AWS Console.

### "App Runner service is not healthy"
**Cause:** Either no Docker image in ECR, or image crashed on startup.
**Fix:** 
1. Verify image exists: `aws ecr describe-images --repository-name ravelgo-backend`
2. Check logs: Go to App Runner console → Service details → Logs
3. Common issues: Missing env vars, database not ready, wrong port

### "Database migration failed: Connection refused"
**Cause:** RDS still spinning up or security group misconfigured.
**Fix:**
1. Wait 2-3 minutes
2. Verify security group allows inbound on port 5432 from App Runner
3. Check RDS is in "Available" state in RDS console

### "curl health check returns 502"
**Cause:** App Runner container crashed.
**Fix:** Check App Runner logs for startup errors. Common issues:
- Missing `NODE_ENV=production`
- Database connection string malformed
- Stripe keys still say `REPLACE_ME`

### "GitHub Actions deployment fails"
**Cause:** Repository variables not set correctly.
**Fix:**
1. Verify all 4 variables exist and have correct values
2. Re-run workflow manually from GitHub Actions tab
3. Check workflow logs for specific error

---

## Next Steps After Deployment

1. **Test the backend:**
   ```bash
   curl -X POST https://xxxxx.awsapprunner.com/trips \
     -H "Content-Type: application/json" \
     -d '{"riderId":"test","source":"...","destination":"..."}'
   ```

2. **Create test Cognito users** via AWS Console for each role (Rider, Driver, Admin)

3. **Connect Flutter apps to real backend:**
   - Update API base URLs in Flutter apps to use App Runner service URL
   - Test login, trip creation, payments

4. **Observe monitoring dashboard:**
   - CloudWatch Metrics tab to see traffic and errors
   - Set up custom dashboards for key metrics

5. **Plan for scale:**
   - Monitor RDS CPU and storage
   - Set up database auto-scaling when traffic increases
   - Consider multi-AZ RDS once you have real users

---

## Rollback

If something goes wrong and you need to delete everything:

```bash
cd infra

# Destroy all stacks (WARNING: deletes all data)
npx cdk destroy --all

# AWS will:
# - Delete EC2 resources (App Runner, RDS snapshot saved)
# - Delete S3 buckets (with contents)
# - Delete Cognito users
# - Keep RDS snapshot for 7 days (for recovery)

# Cost stops immediately
```

**Note:** RDS data is backed up (automated snapshots) so you can restore if needed.

---

## Support

If you encounter issues:

1. **Check AWS Console** CloudFormation events for detailed error messages
2. **Review CloudWatch Logs** in the AWS Console for service errors
3. **Check Prisma schema** if migrations fail (`prisma/schema.prisma`)
4. **Verify environment variables** in App Runner configuration
5. **Test locally first** with Docker: `docker run -e DATABASE_URL="..." ravelgo-backend:latest`

---

**Ready to deploy? Start with Step 1!**
