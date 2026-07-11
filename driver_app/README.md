# RavelGo Driver

The driver-facing Flutter application for RavelGo, built from the Ravel Go Product
Requirement Document. It sits alongside `user_app` (rider app) and `admin_app`
(operations dashboard) in this repository.

## Features

- Driver onboarding: account creation, photo, driver & vehicle information, document
  upload, verification
- Go online/offline, receive and respond to ride requests with fare negotiation
- Active trip flow: in-app messaging, in-app voice call, safety/SOS, trip completion
  and anonymous two-way rider rating
- Trip history, receipts and lost-item reporting
- Document management, including **Car Paddy** vehicle license renewal
- Vehicle management and **Luxury Car Rental** listing
- Earnings dashboard and driver **subscription plans**
- **Driver Assistance Mode** (fuel-efficient routing & hazard alerts)
- Skill-based **incentives & badges**
- Ride preferences used by the driver matching algorithm (language, quiet mode)
- Safety & emergency (SOS, trusted contacts, emergency ride scheduling)
- FAQ & support

## Status

This is a frontend MVP: all data is mocked locally (no backend yet). The
project is structured so a real API/service layer and state management can be
introduced later without reworking the screens.

## Getting started

1. Install the Flutter SDK (this project targets Dart `^3.8.0`).
2. Copy `.env.example` to `.env` and fill in a real `GOOGLE_MAPS_API_KEY`.
3. `flutter pub get`
4. `flutter run`
