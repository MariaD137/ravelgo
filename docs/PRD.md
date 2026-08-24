# RavelGo — Product Requirements Document

**Status:** Draft v1.0
**Owner:** Product
**Last updated:** 2026-08-24
**Related docs:** [`README.md`](../README.md) · [`DEPLOYMENT.md`](../DEPLOYMENT.md) · [`EXECUTIVE-SUMMARY.md`](../EXECUTIVE-SUMMARY.md) · [`TODO.md`](../TODO.md) · [`CRITICAL-REVIEW.md`](../CRITICAL-REVIEW.md)

---

## 1. Summary

RavelGo is a multi-service mobility platform combining ride-hailing, luxury
car rental, courier/delivery, and vehicle license renewal ("Car Paddy") into
one rider app, backed by a dedicated driver app and an internal admin/ops
app. The goal is to offer riders a single app for "get me there, get it
delivered, or rent something nicer" while giving drivers multiple ways to
earn on the same platform, and giving operations a single console to run the
business.

This PRD describes the product as currently scoped and implemented (three
Flutter apps + Node/Express/Prisma backend + AWS CDK infrastructure), and the
requirements for taking it from "UI-complete MVP on mock data" to a launched,
operating platform in one city.

## 2. Problem statement

- Riders juggle separate apps for taxis, courier/delivery, and occasional
  premium/rental car needs, each with its own account, payment method, and
  trust relationship.
- Independent and fleet drivers want more than one way to earn (standard
  rides, premium rentals, deliveries) without switching platforms or
  employers.
- Vehicle owners in the target market face friction renewing vehicle
  licenses/permits — a recurring, low-trust, paperwork-heavy task ("Car
  Paddy") that has no clear self-serve digital option.
- Operators need a single console to manage supply (drivers), demand
  (riders), pricing, disputes, and payouts instead of stitching together
  spreadsheets and support tickets.

## 3. Goals

### 3.1 Product goals
- Ship one rider-facing app that unifies four services: **rides**, **luxury
  car rental**, **courier/delivery**, and **Car Paddy** (vehicle license
  renewal).
- Ship a driver app covering onboarding, document verification, going
  online/offline, trip/job matching, in-trip tools, earnings, payouts, and
  subscriptions.
- Ship an admin app giving operations real-time visibility and control over
  trips, users, drivers, pricing, promotions, loyalty, and support.
- Keep infrastructure cost low enough to be viable pre-revenue (target:
  under $50/month at MVP scale) while having a clear, incremental scaling
  path.

### 3.2 Business goals
- Reach a working, monitored soft launch in **one city** with a minimum
  viable driver supply (50+ verified drivers) before opening to the general
  public.
- Generate platform revenue via **commission on rides** (configurable,
  default 20%), **driver subscriptions**, **surge pricing**, and
  **promotions/loyalty**-driven retention.
- Establish unit economics visibility (cost per trip, driver earnings per
  hour, take rate) from week one of soft launch.

### 3.3 Non-goals (for this version)
- Multi-region / multi-country operation (single AWS region at launch).
- ML-driven dynamic surge pricing (manual/admin-configured surge zones only).
- In-app voice/video calling (mocked/deferred; real telephony is future
  work).
- Automated (computer-vision) driver document verification (manual review at
  launch).
- Public API / third-party integrations beyond Stripe and Google Maps.

## 4. Target users & personas

| Persona | Description | Primary needs |
|---|---|---|
| **Rider** | Everyday commuter/consumer in the launch city | Fast, reliable, fairly priced rides; ability to also book a nicer car, send a package, or renew a vehicle license without leaving the app |
| **Standard driver** | Owns/leases a personal vehicle, drives part- or full-time | Steady ride requests, transparent fares, fast/reliable payouts, low friction onboarding |
| **Premium/rental driver** | Operates a higher-end vehicle for the luxury rental line | Access to higher-fare rental bookings, vehicle-specific document tracking |
| **Courier driver** | Fulfills delivery/courier jobs (may overlap with standard drivers) | Simple pickup/dropoff jobs, proof of delivery, fast payout |
| **Ops/Admin user** | Internal staff running city operations | Real-time visibility into trips/drivers/riders, ability to intervene (suspend, refund, dispatch), pricing and promo control |
| **Vehicle owner (Car Paddy)** | May or may not be an active rider/driver | Simple way to submit vehicle info and renew a license/permit digitally |

## 5. Scope: the four rider-facing services

### 5.1 Rides (core)
- Request a ride with pickup/dropoff, see fare estimate before booking.
- Real-time driver matching and live location tracking during the trip.
- In-trip messaging and an emergency/SOS action.
- Trip completion, receipt, and rating for both rider and driver.
- Trip history.

### 5.2 Luxury car rental
- Browse and book a premium/luxury vehicle for a defined period, distinct
  from an on-demand ride.
- Rental-specific vehicle listings, pricing, and driver assignment.

### 5.3 Courier / delivery
- Book a courier job (pickup and delivery of a package rather than a
  passenger).
- Driver-side job acceptance and delivery confirmation flow, separate from
  passenger trip UX but sharing the matching/dispatch backbone.

### 5.4 Car Paddy (vehicle license renewal)
- Submit vehicle and owner details for license/permit renewal.
- Track renewal request status.
- Present as a distinct, non-mobility "utility" service inside the same app
  to increase engagement between rides.

## 6. Functional requirements by app

### 6.1 Rider app (`user_app/`)
| Area | Requirement |
|---|---|
| Auth | Sign up / sign in via email or phone (Amazon Cognito) |
| Booking | Select service (ride / rental / courier / Car Paddy), enter pickup/dropoff, see fare estimate |
| Driver discovery | View nearby available drivers on a map with live location |
| Trip | Live trip tracking, in-trip messaging, emergency SOS |
| Payments | Add/manage payment method, pay via Stripe, receive receipt |
| History & ratings | View past trips, rate driver, view/download receipts |
| Account | Profile management, referral code, loyalty tier, promotions/discount codes |
| Notifications | Push notifications for trip status changes (post-MVP: see §9) |

### 6.2 Driver app (`driver_app/`)
| Area | Requirement |
|---|---|
| Onboarding | Registration, document upload (license, insurance, vehicle registration), verification status |
| Availability | Go online/offline |
| Job matching | Receive ride/rental/courier requests, accept/decline, fare visibility |
| Active trip | Navigation handoff, in-trip messaging/calling, safety tools |
| Earnings | Trip history, earnings dashboard, incentive/badge tracking |
| Payouts | Bank account linking, weekly/monthly payout schedule and history |
| Subscriptions | Opt into paid subscription tiers for platform benefits (e.g., reduced commission) |
| Vehicles & documents | Manage vehicle(s) and keep compliance documents current |
| Support | In-app support/assistance flow |

### 6.3 Admin app (`admin_app/`)
| Area | Requirement |
|---|---|
| Dashboard | Real-time KPIs: active trips, revenue, ride volume |
| Driver management | Review/approve documents, verify, suspend, manage payouts |
| Rider management | View rider accounts and trip history |
| Trip oversight | Monitor active/past trips, resolve disputes |
| Pricing & surge | Configure base pricing and surge zones/multipliers without a redeploy |
| Promotions & loyalty | Create discount codes, manage loyalty tiers/rewards |
| Rentals & Car Paddy ops | Manage luxury rental inventory/bookings and Car Paddy renewal requests |
| Safety | Fraud alerts, emergency escalation |
| Support | Handle support tickets tied to riders/drivers/trips |
| Reports | Generate/export operational reports |

### 6.4 Backend (`backend/`)
The backend is the shared REST + WebSocket API for all three apps, covering
(per the current route set): admin, alerts, billing, Car Paddy, courier,
documents, drivers, loyalty, payments, payouts, pricing, rentals, riders,
subscriptions, support, trips, uploads, and vehicles — plus OpenAPI docs and
health checks. Requirements:
- All state-changing endpoints require authenticated, role-scoped access
  (rider / driver / admin) via Cognito.
- Trip lifecycle (request → match → in-progress → complete) is transactional
  and drives real-time WebSocket pushes to rider and driver.
- Payment capture goes through Stripe; no card data is stored by RavelGo.
- Driver payouts are calculated on a weekly/monthly schedule at a
  configurable platform commission (default 20%) and paid out via Stripe
  Connect.
- Every endpoint returns a standardized error shape with validation details.
- Rate limiting is applied per user (baseline: 300 requests/15 min).

## 7. Non-functional requirements

| Category | Requirement |
|---|---|
| **Availability** | Backend and database run in a single AWS region/AZ at MVP; target reasonable uptime for a pre-scale product (formal SLA deferred to post-soft-launch) |
| **Performance** | Backend must sustain the soft-launch city's expected concurrent load (see §10, load testing) without degraded trip-matching latency |
| **Security** | TLS everywhere; secrets in AWS Secrets Manager (no hardcoded keys); Cognito-issued, role-scoped auth; Stripe handles all card data (PCI scope minimized) |
| **Privacy** | Rider/driver PII (documents, location, payment metadata) stored only as needed for operation; document uploads stored in S3 behind access control |
| **Auditability** | Admin actions are logged; API activity flows to CloudWatch |
| **Cost** | MVP infrastructure operates within roughly $25–40/month; documented scaling tiers as DAU grows (see `EXECUTIVE-SUMMARY.md`) |
| **Observability** | CloudWatch alarms on errors, CPU, storage, and budget at minimum; deeper APM/log search is a should-have before public launch |

## 8. Business model & pricing

- **Platform commission**: default 20% of ride fare, configurable by admins
  per market without a redeploy.
- **Driver subscriptions**: recurring plans offering platform benefits (e.g.
  reduced commission, priority support) — benefit structure and pricing
  tiers must be finalized before launch (currently unclear per
  `CRITICAL-REVIEW.md`).
- **Surge pricing**: admin-configured multipliers by geography/time; not
  algorithmic in this version.
- **Loyalty & promotions**: tiered rider rewards and admin-issued discount
  codes to support retention and acquisition.
- **Recommendation carried into this PRD**: commission should start lower
  (e.g. 15%) to win initial driver supply, with a defined path to increase
  once liquidity is established — to be confirmed by Product/Finance before
  launch pricing is locked.

## 9. Current state vs. requirements gap

The three Flutter apps are **UI-complete MVPs running on mock data**; the
backend, database schema, and infrastructure are implemented and validated
(build/synth/boot-tested) but **not yet wired to the live apps**. This PRD
treats the following as launch-blocking requirements, not nice-to-haves:

1. **Live backend integration** — replace mock data in all three apps with
   real API calls; validate auth (Cognito), trip lifecycle, and payments
   end-to-end.
2. **Stripe Connect payouts** — the payout calculation exists, but actual
   ACH transfer to driver bank accounts is not wired up; this must work
   before the first payout cycle.
3. **Load testing** — current infra (single App Runner instance, RDS
   `db.t4g.micro`) is untested above light load; must be validated against
   expected soft-launch concurrency, with a caching layer or instance
   upgrade if needed.
4. **End-to-end automated tests** — trip lifecycle, payment flow, and
   WebSocket reconnect behavior need E2E coverage beyond current unit/
   integration tests (~70% coverage).

## 10. Launch requirements (must-have before public launch)

1. Real backend integration across all three apps (no mock data in
   production builds).
2. End-to-end tests covering the full trip lifecycle and payment flow.
3. Stripe Connect fully wired for driver payouts, including failure/retry
   handling.
4. Load testing validated for the launch city's expected concurrency, with
   infrastructure sized accordingly.
5. Minimum viable driver supply secured in the launch city (target: 50+
   verified drivers) before opening rider signups broadly.
6. Basic customer support path (in-app contact, support email, FAQ, refund/
   dispute workflow for driver-cancelled or misbilled trips).
7. API documentation complete (OpenAPI/Swagger) and request/response
   validation standardized across endpoints.

### Should-have (first weeks post-launch)
- Custom domain + DNS/SSL.
- Deeper observability (APM, log search/aggregation dashboards).
- Security scanning in CI (dependency audit, secret scanning, SAST).
- Deep linking and referral link sharing in the rider app.
- Real-time (WebSocket-driven) admin dashboard instead of polling.

### Nice-to-have (later phases)
- Database auto-scaling (read replicas, RDS Proxy).
- Blue-green deployments with automated rollback.
- Offline mode for the driver app (queued jobs/messages when connectivity
  drops).
- Multi-region expansion.
- ML-driven surge pricing.
- Computer-vision-assisted driver document verification.

## 11. Success metrics

| Metric | Target at soft launch | Notes |
|---|---|---|
| Driver supply | 50+ verified, active drivers in launch city | Precondition to opening rider signups |
| Rider pickup wait time | Under a defined threshold (e.g. <10 min median) | To be set with Ops based on city density |
| Trip completion rate | High completion, low cancellation-after-match rate | Signals supply/demand balance |
| Payout accuracy | 100% of scheduled payouts processed correctly and on time | Directly tied to driver retention |
| Backend error rate | Within CloudWatch alarm thresholds under real load | Validated via load testing before launch |
| Support ticket resolution | Defined SLA once support workflow is live | To be set once support tooling is selected |
| Unit economics | Cost per trip and driver earnings/hour tracked from day 1 | Feeds the commission-rate decision in §8 |

## 12. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Driver supply shortage at launch → riders experience long waits → churn | High if unaddressed | Recruit and guarantee minimum earnings for 50+ drivers before public rider acquisition (see §10) |
| Mock-data apps fail against real backend on first integration | High if untested | Treat backend integration + E2E testing as launch-blocking, not post-launch (see §9–10) |
| Backend cannot sustain launch-day concurrency | Medium-high, untested | Load test before launch; have a caching layer / instance upgrade ready |
| Driver payouts fail on first cycle (Stripe Connect incomplete) | High if unaddressed | Complete and test Stripe Connect end-to-end before week-2 payout cycle |
| 20% commission insufficient to retain drivers at scale | Medium, longer-term | Track unit economics from day 1; consider starting lower (§8) |
| No customer support path at launch → disputes become chargebacks | Medium-high if unaddressed | Minimum support workflow is launch-blocking (see §10) |
| Regulatory/licensing exposure, especially for Car Paddy (vehicle licensing) and luxury rental lines | Unknown, needs legal review | Confirm licensing/insurance requirements per jurisdiction before public launch |

## 13. Open questions

- What is the target launch city, and what regulatory/licensing constraints
  apply there (ride-hailing permits, courier regulations, vehicle license
  renewal partnerships for Car Paddy)?
- What are the final driver subscription tiers and their concrete benefits?
- What is the finalized commission rate strategy (start at 20% vs. lower
  introductory rate)?
- What third-party support tool (e.g. Intercom/Zendesk-equivalent) will
  back the in-app support flow?
- Does Car Paddy require a data/API partnership with a government or DMV-
  equivalent body, or is it a manual-processing workflow behind the scenes?
- What is the real-money guarantee/incentive budget for initial driver
  recruitment, and who owns that spend?

## 14. Appendix: current technical stack

- **Rider/Driver/Admin apps**: Flutter (Dart), shared component patterns,
  currently mock-data-driven, structured for real backend integration.
- **Backend**: Node.js + Express + TypeScript, Prisma ORM, WebSocket for
  real-time location/trip-status push, Stripe for payments.
- **Database**: PostgreSQL (AWS RDS), schema covers trips, riders, drivers,
  vehicles, documents, payments, payouts, subscriptions, loyalty,
  promotions, pricing/surge, courier, rentals, Car Paddy, alerts, and
  support.
- **Infrastructure**: AWS CDK — VPC (no NAT gateway, cost-optimized), RDS
  PostgreSQL, App Runner, ECR, CloudFront, Secrets Manager, CloudWatch.
- **CI/CD**: GitHub Actions with GitHub OIDC (no long-lived AWS keys),
  automated Docker build/push to ECR.
- **Auth**: Amazon Cognito with rider/driver/admin roles.
