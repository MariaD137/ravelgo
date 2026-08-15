# Repository Structure

```
ravelgo/
├── .github/
│   └── workflows/
│       ├── backend-ci.yml          # Lint, typecheck, test, build on PRs
│       ├── backend-deploy.yml      # Build Docker image, deploy to App Runner on main push
│       ├── flutter-ci.yml          # Analyze and test all three Flutter apps on PRs
│       └── infra-ci.yml            # CDK synth validation on infra PRs
│
├── admin_app/                      # Flutter admin dashboard app
│   ├── lib/
│   │   ├── main.dart               # App entry point
│   │   ├── models/                 # Data models (car_paddy, courier, driver, etc.)
│   │   ├── theme/                  # App theming
│   │   └── utils/                  # Shared utilities
│   ├── assets/                     # Images, icons
│   ├── android/                    # Android platform config
│   ├── ios/                        # iOS platform config
│   ├── pubspec.yaml                # Dart dependencies
│   └── .env.example                # Required env vars template
│
├── backend/                        # Node.js/Express API server
│   ├── src/
│   │   ├── index.ts                # Server entry point
│   │   ├── app.ts                  # Express app setup (middleware, routes)
│   │   ├── config/
│   │   │   └── env.ts              # Environment variable loading and validation
│   │   ├── db/
│   │   │   └── prisma.ts           # Prisma client singleton
│   │   ├── middleware/
│   │   │   ├── auth.ts             # Cognito JWT verification
│   │   │   └── error-handler.ts    # Centralized error handling
│   │   ├── lib/
│   │   │   ├── errors.ts           # Typed error classes
│   │   │   ├── pagination.ts       # Pagination helpers
│   │   │   └── validate.ts         # Zod validation middleware
│   │   ├── routes/                 # Express route handlers + co-located tests
│   │   │   ├── admin.routes.ts
│   │   │   ├── alerts.routes.ts
│   │   │   ├── billing.routes.ts
│   │   │   ├── carpaddy.routes.ts
│   │   │   ├── courier.routes.ts
│   │   │   ├── documents.routes.ts
│   │   │   ├── drivers.routes.ts
│   │   │   ├── health.routes.ts
│   │   │   ├── loyalty.routes.ts
│   │   │   ├── payments.routes.ts
│   │   │   ├── payouts.routes.ts
│   │   │   ├── pricing.routes.ts
│   │   │   ├── rentals.routes.ts
│   │   │   ├── riders.routes.ts
│   │   │   ├── subscriptions.routes.ts
│   │   │   ├── support.routes.ts
│   │   │   ├── trips.routes.ts
│   │   │   ├── uploads.routes.ts
│   │   │   └── vehicles.routes.ts
│   │   ├── billing/
│   │   │   └── stripe.ts           # Stripe client and helpers
│   │   ├── services/
│   │   │   ├── matching.ts         # Driver-ride matching logic
│   │   │   └── payouts.ts          # Driver payout processing
│   │   ├── realtime/
│   │   │   ├── hub.ts              # WebSocket event hub
│   │   │   └── server.ts           # WS server setup
│   │   └── test/
│   │       └── helpers.ts          # Test utilities (mock auth, DB setup)
│   ├── prisma/
│   │   ├── schema.prisma           # Database schema
│   │   └── seed.ts                 # Seed data for development
│   ├── Dockerfile                  # Multi-stage Docker build
│   ├── package.json
│   ├── tsconfig.json
│   ├── eslint.config.js
│   ├── openapi.yaml                # API specification
│   └── .env.example                # Required env vars template
│
├── driver_app/                     # Flutter driver app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/                 # Driver, vehicle, ride, document models
│   │   ├── theme/
│   │   └── utils/
│   ├── assets/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── .env.example
│
├── infra/                          # AWS CDK infrastructure-as-code
│   ├── bin/
│   │   └── infra.ts                # CDK app entry point
│   ├── lib/
│   │   ├── network-stack.ts        # VPC, subnets
│   │   ├── auth-stack.ts           # Cognito
│   │   ├── data-stack.ts           # RDS PostgreSQL
│   │   ├── storage-stack.ts        # S3 buckets
│   │   ├── api-stack.ts            # ECR + App Runner
│   │   ├── monitoring-stack.ts     # CloudWatch + SNS
│   │   └── ci-stack.ts             # GitHub OIDC + IAM deploy role
│   ├── cdk.json
│   ├── package.json
│   └── tsconfig.json
│
├── docs/                           # Documentation
│   ├── ARCHITECTURE.md
│   ├── REPOSITORY-STRUCTURE.md
│   ├── AWS-DEPLOYMENT.md
│   ├── DEPLOYMENT-CHECKLIST.md
│   ├── admin-bootstrap.md
│   └── realtime-architecture.md
│
├── CRITICAL-REVIEW.md              # Honest platform assessment
├── DEPLOYMENT-QUICKSTART.md        # Quick deployment guide
├── DEPLOYMENT.md                   # Full deployment documentation
├── EXECUTIVE-SUMMARY.md            # CEO/stakeholder summary
├── README.md                       # Project overview
└── TODO.md                         # Remaining work tracker
```

## What Each Directory Does

| Directory | Purpose | Language | Deployed Where |
|---|---|---|---|
| `admin_app/` | Admin dashboard mobile app | Flutter/Dart | App stores (not yet) |
| `backend/` | Unified REST + WebSocket API | TypeScript/Node.js | AWS App Runner |
| `driver_app/` | Driver mobile app | Flutter/Dart | App stores (not yet) |
| `infra/` | AWS infrastructure definitions | TypeScript/CDK | AWS CloudFormation |
| `user_app/` | Rider mobile app | Flutter/Dart | App stores (not yet) |
| `docs/` | Technical documentation | Markdown | N/A |
| `.github/workflows/` | CI/CD pipelines | YAML | GitHub Actions |
