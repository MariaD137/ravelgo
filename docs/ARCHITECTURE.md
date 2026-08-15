# RavelGo Architecture

## Application Overview

RavelGo is a premium ride-hailing and vehicle-rental marketplace with three Flutter mobile apps and a shared Node.js/Express backend, deployed on AWS via CDK.

## Technology Stack

| Layer | Technology |
|---|---|
| Mobile apps | Flutter/Dart (user_app, driver_app, admin_app) |
| Backend API | Node.js 22, Express 4, TypeScript |
| Database | PostgreSQL 16 via Prisma ORM |
| Auth | AWS Cognito (JWT verification via aws-jwt-verify) |
| Payments | Stripe (payments, webhooks, driver payouts) |
| Real-time | WebSocket server (ws library) |
| File storage | AWS S3 (presigned URLs for driver documents and assets) |
| Infrastructure | AWS CDK (TypeScript) |
| Compute | AWS App Runner (Docker container) |
| CI/CD | GitHub Actions (backend-ci, backend-deploy, flutter-ci, infra-ci) |

## Frontend (Flutter)

Three Flutter apps share identical asset sets and similar structure:

- **user_app** - Rider-facing: ride requests, trip tracking, payments, ride history
- **driver_app** - Driver-facing: ride acceptance, navigation, documents, earnings
- **admin_app** - Admin-facing: dashboards, user/driver management, disputes, alerts

All three currently run on mock data and need backend integration.

## Backend API

Express application at `backend/` with:

- **Routes**: riders, drivers, vehicles, trips, rentals, courier, billing, payments, payouts, subscriptions, loyalty, pricing, alerts, support, documents, uploads, admin, health
- **Middleware**: Cognito JWT auth, rate limiting (express-rate-limit), Helmet, CORS, Morgan logging
- **Services**: ride matching (matching.ts), payouts (payouts.ts), Stripe billing (stripe.ts)
- **Real-time**: WebSocket hub for driver location, trip status, ride requests
- **Validation**: Zod schemas
- **Error handling**: Centralized error handler with typed errors

## Database

PostgreSQL with Prisma ORM. Key models:

- **Identity**: User, Driver, DriverDocument, DriverBankAccount
- **Vehicles**: Vehicle, RentalListing
- **Trips**: Trip (ride-hailing), CarPaddyRequest, CourierRequest
- **Financial**: Payment, Payout, SubscriptionPlan, DriverSubscription
- **Platform**: SupportTicket, EmergencyAlert, LoyaltyTier, Promotion, PricingRule, SurgeZone

Migrations managed via `prisma migrate`.

## Authentication

AWS Cognito user pools. Backend verifies JWTs using `aws-jwt-verify`. CDK deploys Cognito via `auth-stack.ts`.

## Payments

Stripe for card payments, webhook processing, and driver payouts. Backend routes handle payment creation, webhook signature verification, and payout processing.

## Infrastructure (CDK)

Seven CDK stacks in `infra/`:

| Stack | Purpose |
|---|---|
| network-stack | VPC, subnets, security groups |
| auth-stack | Cognito user pool and client |
| data-stack | RDS PostgreSQL instance |
| storage-stack | S3 buckets (documents, assets) |
| api-stack | ECR, App Runner service |
| monitoring-stack | CloudWatch alarms, SNS alerts |
| ci-stack | GitHub OIDC provider, IAM deploy role |

## Deployment

- Backend deploys to AWS App Runner via `backend-deploy.yml` on push to `main`
- Uses GitHub OIDC for AWS authentication (no long-lived secrets)
- Docker image built and pushed to ECR, then App Runner redeploys
- Flutter apps are not yet deployed (no app store pipelines)

## Testing

- Backend: Node.js built-in test runner with test files per route
- Flutter: Default widget tests (minimal)
- CI runs lint, typecheck, build, and test for backend on every PR

## Major Dependencies

- express, prisma, stripe, ws, zod, helmet, express-rate-limit
- aws-sdk (S3), aws-jwt-verify (Cognito)
- aws-cdk-lib (infrastructure)

## Highly Coupled Areas

- Trip lifecycle spans: trips routes, matching service, real-time hub, payment routes, payout service
- Driver onboarding spans: drivers routes, documents routes, admin routes

## Potentially Isolatable Areas

- Courier service (independent of ride-hailing)
- Rental listings (independent of ride-hailing trips)
- Loyalty/promotions (read-only coupling to trips)
- Support tickets (loosely coupled)

## Current Risks

1. Flutter apps use mock data; no end-to-end integration tested
2. No load testing performed
3. No staging environment
4. No audit logging for admin actions
5. WebSocket server is in-process (single instance limitation)
6. No caching layer (every request hits DB directly)
