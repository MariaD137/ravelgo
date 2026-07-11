# RavelGo

RavelGo is a ride-hailing platform (rides, luxury car rental, courier/delivery,
and vehicle license renewal via "Car Paddy") built from the Ravel Go Product
Requirement Document. This repo contains three independent Flutter apps:

| App | Folder | Description |
|---|---|---|
| Rider | [`user_app/`](./user_app) | The rider-facing app: booking, tracking, services, account |
| Driver | [`driver_app/`](./driver_app) | The driver-facing app: onboarding, trips, earnings, documents |
| Admin | [`admin_app/`](./admin_app) | The operations/back-office dashboard |

## Status

All three apps are frontend MVPs: screens and flows are built out with local
mock data, and there is no backend yet. Each app is structured so a real
API/service layer and state management can be introduced later without
reworking the UI.

## Getting started

Each app is a standalone Flutter project. From inside an app's folder:

1. Install the Flutter SDK.
2. Copy `.env.example` to `.env` and fill in a real `GOOGLE_MAPS_API_KEY`.
3. Copy `android/local.properties.example` to `android/local.properties` and
   set your Android SDK path and `maps.apiKey`.
4. `flutter pub get`
5. `flutter run`

See each app's own `README.md` for its specific feature set.
