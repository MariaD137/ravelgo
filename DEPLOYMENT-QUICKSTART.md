# 🚀 RavelGo AWS Deployment Quick Start

**You haven't deployed to AWS yet.** This is your deployment roadmap.

---

## 📋 Current Status

✅ **Complete:**
- Backend API (Express + TypeScript + Prisma)
- All 3 Flutter apps (user/driver/admin MVPs with mock data)
- AWS infrastructure-as-code (CDK with 7 stacks)
- GitHub Actions CI/CD pipeline
- Real-time WebSocket system
- Stripe payment processing
- Cognito authentication
- Monitoring (CloudWatch alarms + budget alerts)

⏳ **Not Yet Done:**
- AWS deployment (infrastructure not yet created)
- Database creation and seeding
- First Docker image pushed to ECR
- Flutter apps connected to real backend
- GitHub Actions wired up
- First Stripe webhook processed

---

## 🎯 Deployment Timeline

```
Pre-deployment checks (15 min)
         ↓
CDK Bootstrap (5 min)
         ↓
Infrastructure Deploy (25-30 min) ← RDS takes 10-15 min
         ↓
Stripe Config (2 min)
         ↓
Push Backend Docker Image (5 min)
         ↓
Database Setup (3 min)
         ↓
Verification (5 min)
         ↓
✓ Production ready!
```

**Total time: 60-75 minutes** (mostly waiting for AWS)

---

## 🚀 Start Here

### Option 1: Fast Track (Just Deploy)
1. Read `docs/DEPLOYMENT-CHECKLIST.md` 
2. Follow the 10 steps in `docs/AWS-DEPLOYMENT.md`
3. Done! Your backend is live.

### Option 2: Understand First (Recommended)
1. Review architecture: `docs/architecture.md` (if exists) or `infra/README.md`
2. Understand costs: `docs/AWS-DEPLOYMENT.md` → "Cost Breakdown"
3. Follow `docs/DEPLOYMENT-CHECKLIST.md` step by step
4. Use `docs/AWS-DEPLOYMENT.md` for detailed explanations

---

## 📚 Key Documents

| Document | Purpose |
|----------|---------|
| `DEPLOYMENT-CHECKLIST.md` | ☑️ Quick reference checklist (print this!) |
| `AWS-DEPLOYMENT.md` | 📖 Detailed 10-step guide with examples |
| `infra/README.md` | 🏗️ Infrastructure architecture overview |
| `TODO.md` | 📋 Complete platform backlog (28 remaining items) |
| `docs/realtime-architecture.md` | 🔌 WebSocket real-time system design |

---

## 💰 Expected Costs

| Service | Monthly Cost |
|---------|-------------|
| RDS PostgreSQL (db.t4g.micro) | $10-15 |
| App Runner (1 vCPU, 2GB) | $8-12 |
| S3 + CloudFront | $3-7 |
| CloudWatch + SNS | $3-5 |
| Cognito + Secrets | <$1 |
| **Total** | **~$25-40** |

CloudWatch budget alert set to $100/month (safe margin for MVP phase).

---

## 🔧 Prerequisites Checklist

Before deploying, you need:

- [ ] **AWS Account** (with billing enabled)
- [ ] **AWS CLI** installed and configured (`aws configure`)
- [ ] **Node.js 18+** (for CDK)
- [ ] **Docker** (to build backend image)
- [ ] **Stripe Account** with API keys (`sk_live_*` and `whsec_*`)

Verify everything:
```bash
aws sts get-caller-identity      # AWS access
node --version                   # Node 18+
docker --version                 # Docker installed
```

---

## 🚦 Deployment Steps (Abbreviated)

### 1️⃣ Bootstrap CDK
```bash
cd infra
npm install
npx cdk bootstrap aws://<ACCOUNT_ID>/<REGION>
```

### 2️⃣ Deploy Infrastructure
```bash
npx cdk deploy --all
# ⏳ Wait for RDS (10-15 min is normal)
# 💾 Save all outputs!
```

### 3️⃣ Update Stripe Secret
```bash
aws secretsmanager put-secret-value \
  --secret-id <StripeSecretArn> \
  --secret-string '{"secretKey":"sk_live_xxx","webhookSecret":"whsec_xxx"}'
```

### 4️⃣ Push Backend Docker Image
```bash
cd backend
docker build -t ravelgo-backend:latest .
docker tag ravelgo-backend:latest <EcrRepositoryUri>:latest
docker push <EcrRepositoryUri>:latest
# ⏳ App Runner detects and deploys (3-5 min)
```

### 5️⃣ Run Database Migrations
```bash
export DATABASE_URL="postgres://user:pass@host:5432/ravelgo"
npx prisma migrate deploy
```

### 6️⃣ Verify
```bash
curl https://<ServiceUrl>/health
# Should return: {"status":"ok"}
```

### 7️⃣ (Optional) Setup GitHub Actions
Add 4 repository variables in GitHub:
- `AWS_REGION`
- `AWS_DEPLOY_ROLE_ARN`
- `ECR_REPOSITORY_URI`
- `APP_RUNNER_SERVICE_ARN`

Then test: `git push` → automatic deployment!

---

## ⚠️ Common Gotchas

| Issue | Solution |
|-------|----------|
| "Role does not exist" error | Re-run CDK bootstrap, wait 1 min |
| RDS taking >15 min | Normal! AWS is provisioning hardware. Wait. |
| App Runner "not healthy" | Check logs: AWS Console → App Runner → Logs. Usually missing env vars. |
| `curl /health` returns 502 | Container crashed. Check App Runner logs for startup errors. |
| Database migration fails | RDS still starting up. Wait 2-3 min, retry. |

See `docs/AWS-DEPLOYMENT.md` → "Troubleshooting" for detailed fixes.

---

## ✅ Post-Deployment

Once everything is running:

1. **Test the API:**
   ```bash
   curl https://<ServiceUrl>/health
   ```

2. **Create Cognito test users** for Rider/Driver/Admin roles

3. **Update Flutter apps** to use real `ServiceUrl` instead of mock data

4. **Enable GitHub Actions** for automatic deployments on push

5. **Monitor** CloudWatch dashboard and confirm alarms work

6. **Check email** for SNS alert confirmations

---

## 📊 What Gets Created

When you run `cdk deploy --all`:

### AWS Resources
- **7 CloudFormation stacks** (Network, Auth, Storage, Data, Api, Monitoring, CI)
- **VPC** with isolated subnets (no NAT gateway = cheaper)
- **RDS PostgreSQL** database (db.t4g.micro single-AZ)
- **App Runner** service (auto-scaling container)
- **ECR** repository (Docker images)
- **Cognito** user pool (auth for 3 apps)
- **S3 buckets** (driver docs + assets via CloudFront)
- **CloudWatch** alarms (errors, CPU, storage, budget)
- **GitHub OIDC** provider (CI/CD automation)

### What You Configure Afterward
- Stripe keys (secrets rotation)
- Cognito test users (for QA)
- GitHub Actions variables (for CI/CD)
- Flutter app API endpoints (connect to backend)

---

## 🎓 Learning Resources

**Before you deploy, understand:**
1. **Architecture**: `infra/README.md` explains all 7 stacks
2. **Cost model**: `docs/AWS-DEPLOYMENT.md` → Cost Breakdown
3. **What goes wrong**: `docs/AWS-DEPLOYMENT.md` → Troubleshooting

**During deployment:**
- Use `DEPLOYMENT-CHECKLIST.md` as your checklist (print it!)
- Refer to `AWS-DEPLOYMENT.md` for each step's details
- Watch CloudFormation events in AWS Console (Settings → View events)

**After deployment:**
- Test backend: `curl https://<URL>/health`
- Monitor: CloudWatch dashboard
- Explore: AWS Console for your new resources

---

## 🔄 Next Phase (After Deployment)

Once infrastructure is live, priorities are:

1. **Connect Flutter apps** to real backend (remove mock data)
2. **End-to-end tests** (QA-04: trip lifecycle from booking to completion)
3. **Driver payouts** (PAY-03: weekly deposits to driver bank accounts)

See `TODO.md` for full backlog.

---

## 📞 Need Help?

1. **Deployment fails?** → `docs/AWS-DEPLOYMENT.md` → "Troubleshooting"
2. **Cost concerns?** → `docs/AWS-DEPLOYMENT.md` → "Cost Breakdown"
3. **Architecture questions?** → `infra/README.md` for CDK overview
4. **What's next after deploy?** → `TODO.md` priority matrix

---

## 🎯 Success Criteria

Deployment is **complete and successful** when:

- ✅ All 7 CDK stacks created (visible in AWS CloudFormation console)
- ✅ `curl https://<ServiceUrl>/health` returns `{"status":"ok"}`
- ✅ Database migration completed (`\dt` lists all tables)
- ✅ Stripe keys updated (not `REPLACE_ME`)
- ✅ CloudWatch alarms created and email subscriptions confirmed
- ✅ Docker image in ECR and App Runner is RUNNING
- ✅ (Optional) GitHub Actions workflow successfully deployed

**Once all checkmarks are green, your RavelGo backend is production-ready!**

---

## 🚀 Ready to Deploy?

**Next step:** Open `docs/DEPLOYMENT-CHECKLIST.md` and start at "Pre-Deployment"

Questions? Refer to `docs/AWS-DEPLOYMENT.md` for detailed explanations.

Good luck! 🎉
