# RavelGo Admin

The operations/admin Flutter application for RavelGo, built from the Ravel Go
Product Requirement Document. It sits alongside `user_app` (rider app) and
`driver_app` (driver app) in this repository.

The PRD doesn't specify admin features explicitly, so this app covers the
back-office operations implied by the rider/driver features:

- Dashboard with live KPIs and weekly ride/revenue charts
- Driver management: document verification, suspend/reactivate
- Rider management: view history, suspend/reactivate
- Trip monitoring, including flagged/disputed trips
- Courier ("Be a Courier") request queue
- **Car Paddy** vehicle license renewal request review/approval
- **Luxury Car Rental** listing approval
- Pricing & surge configuration, including traffic-based fare discounts
- Driver subscription plan management
- Fraud alerts (AI-based fraud prevention) and emergency/SOS dispatch
- Loyalty program tiers & referral/promo codes
- Support tickets & disputes
- Reports & analytics
- Admin roles & permissions

## Status

This is a frontend MVP: all data is mocked locally (no backend yet). The
project is structured so a real API/service layer and state management can be
introduced later without reworking the screens.

## Getting started

1. Install the Flutter SDK (this project targets Dart `^3.8.0`).
2. Copy `.env.example` to `.env` and fill in a real `GOOGLE_MAPS_API_KEY`.
3. `flutter pub get`
4. `flutter run`
