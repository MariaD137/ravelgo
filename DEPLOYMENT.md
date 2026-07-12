# Deploying RavelGo

This is the full path from a fresh AWS account to a live backend that
redeploys automatically every time you push to `main`, plus how the three
Flutter apps eventually plug into it.

## The pieces

```
GitHub push to main
   │
   ├─ backend/**  changed → Backend CI (lint/typecheck/build)
   │                      → Backend Deploy (build image → ECR → App Runner)
   │
   ├─ infra/**    changed → Infra CI (cdk synth, catches config errors)
   │
   └─ *_app/**    changed → Flutter CI (flutter analyze + test, all 3 apps)
```

- **`backend/`** — Node.js/Express/TypeScript API, Prisma/PostgreSQL, Cognito
  JWT auth. See `backend/README.md`.
- **`infra/`** — AWS CDK app that provisions the VPC, RDS, Cognito, S3,
  App Runner, and the GitHub OIDC role CI uses to deploy. See `infra/README.md`.
- **`.github/workflows/`** — the four pipelines above.

## First-time setup (in order)

1. **Deploy the AWS infrastructure.** Follow `infra/README.md` end to end:
   `cdk bootstrap` → `cdk deploy --all` → push a first image manually → run
   the first Prisma migration. This creates real AWS resources and costs
   real money (see "Cost notes" in `infra/README.md`) — do this when you're
   ready, not experimentally.

2. **Wire GitHub Actions to AWS.** Add the repository variables listed at
   the bottom of `infra/README.md` (`AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`,
   `ECR_REPOSITORY_URI`, `APP_RUNNER_SERVICE_ARN`). No AWS access keys are
   ever stored in GitHub — deploys authenticate via OpenID Connect.

3. **(Recommended) Add a `production` GitHub Environment** with required
   reviewers, so a push to `main` pauses for your approval before
   `backend-deploy.yml` actually touches AWS. GitHub → Settings →
   Environments → New environment → `production`.

4. From here on, **every push to `main` that touches `backend/`
   auto-deploys**. Every pull request touching `backend/`, `infra/`, or any
   of the three Flutter apps gets the matching CI check.

## What's validated vs. what isn't

I built and tested this as much as this sandbox allows without your AWS
account or a real Flutter SDK installed:

| Checked | How |
|---|---|
| Backend compiles, lints, boots, and enforces auth on every route | Ran it directly against a real local Postgres 16 instance: `/health` reports `database: connected`, every protected route (`/api/riders`, `/api/vehicles`, `/api/rentals`, `/api/support-tickets`, `/api/uploads/presign`, etc.) correctly 401s without a token |
| Prisma migration + seed script | Actually applied `prisma migrate dev` and `npm run prisma:seed` against a real Postgres 16 instance — not just type-checked. Verified the seeded rows directly with `psql` |
| CDK app synthesizes to valid CloudFormation | Ran `cdk synth` on all 6 stacks — caught and fixed one real dependency-cycle bug this way |
| Cross-stack wiring (DB host/port/creds, Cognito IDs → App Runner env) | Inspected the synthesized template directly |
| Docker image build | **Not run** — no Docker daemon available in this sandbox. The Dockerfile mirrors the exact build/generate/compile steps already verified above, so it should work, but build it yourself once before relying on it |
| `flutter analyze` / `flutter test` on the three apps | **Not run** — no Flutter SDK in this sandbox. I fixed one broken leftover test (`user_app`'s was the unmodified Flutter counter-app template, testing a counter button that doesn't exist in the real app) but there could be other issues the analyzer would catch that I couldn't run |
| Actual `cdk deploy` / real AWS resources | **Not run** — needs your AWS credentials, which should never be pasted into a chat session. Runs from your machine or from GitHub Actions via OIDC only |

Before you rely on any of this in production: run `docker build` on the
backend yourself once, and run `flutter analyze && flutter test` in each
Flutter app once, to close those two gaps.

## Next step: wiring the Flutter apps to the real API

Right now all three apps run entirely on local mock data (see each app's
`lib/models/*.dart`). To connect them:

1. Add an HTTP client dependency (`http` or `dio`) to each app's `pubspec.yaml`.
2. Add Cognito sign-in (the `amazon_cognito_identity_dart_2` package or AWS
   Amplify Flutter) so each app can obtain a JWT to send as
   `Authorization: Bearer <token>`.
3. Replace the mock data lists/functions in `lib/models/` with calls to the
   backend's `/api/...` endpoints (see `backend/README.md` for what exists
   today — it's a starting slice, not full coverage of every screen).
4. Point each app's `.env` `API_BASE_URL` at the `ServiceUrl` output from
   `cdk deploy`.

This is a substantial follow-up piece of work on its own — happy to do it
next if you want.
