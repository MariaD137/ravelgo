# RavelGo Rider

The rider-facing Flutter application for RavelGo, built from the Ravel Go Product
Requirement Document. It sits alongside `driver_app` (driver app) and `admin_app`
(operations dashboard) in this repository.

## Features

- Account creation, login and profile
- Ride booking and tracking (request, driver search, ride selection, cancellation)
- Services hub: rides, luxury car rental, i-deliva courier/delivery
- Ride history and account settings

## Status

This is a frontend MVP: all data is mocked locally (no backend yet). Note that
this app's naming and some of its screens (e.g. `views/Driver_Portal`) still
carry over from an earlier driver-app-based starting point and have not all
been fully re-themed for the rider experience — see the repo's
`CRITICAL-REVIEW.md` for known gaps.

## Getting started

1. Install the Flutter SDK (this project targets Dart `^3.8.0`).
2. Copy `.env.example` to `.env` and fill in a real `GOOGLE_MAPS_API_KEY`.
3. Copy `android/local.properties.example` to `android/local.properties` and
   set your Android SDK path and `maps.apiKey`.
4. `flutter pub get`
5. `flutter run`
