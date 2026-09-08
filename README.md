# RavelGo

RavelGo is a ride-hailing platform (rides, luxury car rental, courier/delivery,
and vehicle license renewal via "Car Paddy") built from the Ravel Go Product
Requirement Document.

| Component | Folder | Description |
|---|---|---|
| Rider app | [`user_app/`](./user_app) | Flutter: booking, tracking, services, account |
| Driver app | [`driver_app/`](./driver_app) | Flutter: onboarding, trips, earnings, documents |
| Admin app | [`admin_app/`](./admin_app) | Flutter: operations/back-office dashboard |
| Backend | [`backend/`](./backend) | Node.js/Express API shared by all three apps |
| Infrastructure | [`infra/`](./infra) | AWS CDK — provisions everything the backend runs on |

See [`docs/DEPLOY-RUNBOOK.md`](./docs/DEPLOY-RUNBOOK.md) for the full path
from a fresh AWS account to a live, auto-deploying backend, and
[`docs/admin-bootstrap.md`](./docs/admin-bootstrap.md) for how to create the
first Admin user once Cognito is deployed.

## Status

The three Flutter apps call the real backend API (no mock data) and the
backend, infrastructure, and CI/CD pipeline are deployed to a live AWS
staging environment — see [`docs/DEPLOY-RUNBOOK.md`](./docs/DEPLOY-RUNBOOK.md)
for the deploy/migrate/seed process. Older planning and audit documents that
predate this state have been moved to [`docs/archive/`](./docs/archive).

## Getting started

Each app is a standalone Flutter project. From inside an app's folder:

1. Install the Flutter SDK.
2. Copy `.env.example` to `.env` and fill in a real `GOOGLE_MAPS_API_KEY`.
3. Copy `android/local.properties.example` to `android/local.properties` and
   set your Android SDK path and `maps.apiKey`.
4. `flutter pub get`
5. `flutter run`

See each app's own `README.md` for its specific feature set.
