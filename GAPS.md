# RavelGo — Gap Register

**Date:** 2026-08-29
**Scope:** whole monorepo — `user_app`, `driver_app`, `admin_app`, `backend`, `infra`.
**How this was built:** traced the actual code and API surface, ran the backend suite (115/115), `flutter analyze`/`test` on all three apps, and `cdk synth`. Gaps are what *isn't* wired or is only mock — not a wish-list. Severity is about shipping a real product, and each item is tagged whether it's a true gap or a deliberate MVP scope decision.

> Supersedes the stale `TODO.md` (dated 2026-07-29, which predates this session — it still lists the driver payout system as "not started," but that system is built and tested).

---

## 0. The one fact that frames everything

**The three Flutter apps have no connection to the backend at all.** No HTTP client, no authentication, no Stripe SDK are even declared as dependencies (`pubspec.yaml` in all three). Every screen runs on local mock/session state held in three `ChangeNotifier` singletons (`user_app` `RiderAppState`, `driver_app` `DriverEarningsState`, `admin_app` `AdminActionsState`). The only network call in any app hits Google Maps, not RavelGo.

So the backend can be excellent (it largely is) and **nothing works end-to-end**, because the front end can't reach it. This is the root of most "🔴 Blocker" items below.

---

## 1. 🔴 Blockers — nothing runs end-to-end until these exist

| # | Gap | Where | Notes |
|---|---|---|---|
| B-1 | **No API client in any Flutter app** | all 3 apps | No `http`/`dio`; no base-URL wiring (`API_BASE_URL` sits unused in `.env.example`). Every list, form, and action is local state. |
| B-2 | **No authentication in Flutter** | all 3 apps | No Cognito/Amplify SDK; login screens validate input then show an honest "not connected" boundary. Without a real access token, *no* authenticated endpoint (wallet, trips, payments, everything) is reachable. |
| B-3 | **Backend is not deployed anywhere** | infra | No AWS account is wired into the repo. There is no reachable API URL, no live database, no live Cognito pool. `cdk synth` passes; nothing is deployed. |
| B-4 | **Stripe not integrated** (acknowledged, coming later) | backend + Flutter | Server-side PaymentIntent + signed webhook exist; the Flutter side (publishable key + PaymentSheet) does not, and infra Stripe keys are placeholders. Wallet *funding* also depends on this. |

## 2. 🟠 Payments — real gaps beyond Stripe integration

| # | Gap | Where | Notes |
|---|---|---|---|
| P-1 | **Card `clientSecret` has no path to the rider** | `payments.routes.ts` | Charge is Driver/Admin-only; the CARD `clientSecret` is returned in the *driver's* response with no channel to the rider's device to confirm a PaymentSheet. Card can't complete end-to-end even once Stripe is added, until this is designed (rider-initiated confirm, or off-session saved-card charge). |
| P-2 | **A failed card payment can't be retried** | `payments.routes.ts` | `Payment` is unique per `tripId`; once a row exists (even `FAILED`), re-charging returns 409. A decline permanently strands the trip's payment. |
| P-3 | **`REFUNDED` is an enum value with no transition** | schema + routes | No refund endpoint exists; the admin app's "refund" is local-state only. Nothing can legitimately move a payment to `REFUNDED`. |
| P-4 | **Driver payout doesn't actually move money** | `services/payouts.ts:144` | `processPayout` is a `// TODO: integrate Stripe Connect` simulation — sets `PROCESSING` with a fake transaction id. Real bank verification + ACH transfer (Stripe Connect) is not built. Amounts/ledger are correct; the disbursement is not real. |
| P-5 | **Wallet can be spent but not funded without Stripe** | `wallet.routes.ts` | Spend (debit) is Stripe-free and complete; top-up is a Stripe PaymentIntent. So the wallet is only half a standalone feature until Stripe lands. |
| P-6 | **Monetary columns are SQL `Float`** | schema | `Trip.estimatedFare/finalFare`, `Payment.amount` are floats. Rounding is applied everywhere so no drift is observed, but integer minor units would be the stronger representation. Wallet balance already uses integer cents. |

## 3. 🟡 Backend feature gaps — endpoints the apps need but that don't exist

| # | Gap | Notes |
|---|---|---|
| A-1 | **No notification service/endpoint** | All three apps have a Notifications screen showing an honest empty state. There is no backend to deliver ride/payout/incentive/ops notifications, and no push (FCM/APNs). |
| A-2 | **Rider can't cancel their own trip via API** | `PATCH /trips/:id/status` is Driver/Admin-only. A rider-initiated cancel (with policy/fee) has no endpoint. |
| A-3 | **No in-app messaging / trip chat** | Rider↔driver contact in the apps is clipboard-copy stubs; no backend conversation store. |
| A-4 | **No admin audit logging** | Admin actions (refund, suspend, approve/reject, dispatch) aren't recorded to an immutable audit trail. |
| A-5 | **No analytics/reporting queries** | The admin "Export report" builds a CSV from on-screen demo data client-side; there is no backend analytics/export. |
| A-6 | **No real fraud detection or safety dispatch** | `emergency-alerts` can be created/listed/resolved, but there is no scoring, no responder dispatch, no trusted-contact notification backend. |
| A-7 | **Loyalty advancement & referral rewards are thin** | Tiers/promotions models + redemption exist; automatic tier advancement and referral reward distribution logic do not. |
| A-8 | **Document/vehicle verification is metadata-only** | `POST /documents` records a `fileKey`; there's no content inspection, expiry automation, or verification workflow beyond an admin APPROVE/REJECT. |

## 4. 🟡 Realtime, matching & scale

| # | Gap | Where | Notes |
|---|---|---|---|
| R-1 | **Realtime hub is in-memory (single instance only)** | `realtime/hub.ts` | Trip rooms + driver locations live in a process `Map`. Correct for one App Runner instance; breaks the moment it scales past one. Needs a shared store (Redis/ElastiCache) or a managed pub/sub. |
| R-2 | **Rate limiter is in-memory (single instance only)** | `middleware/rate-limit.ts` | Same caveat — per-instance counters reset per instance under horizontal scaling. |
| R-3 | **No geocoding/routing — distance is client-supplied** | `trips.routes.ts`, `pricing` | Fare *rate* is authoritative, but the distance/duration it's applied to are asserted by the client (no Maps Distance Matrix / routing). A rider can under-report distance. `baseFare` is the only floor. |
| R-4 | **Matching is naive** | `services/matching.ts` | "First available `ACTIVE` driver, highest-rated," run inline in the request. Not location-aware (no persisted driver location to query), no queue/retry for unmatched trips, no driver accept/decline handshake. |
| R-5 | **No driver presence/online system** | `drivers.routes.ts` (noted out of scope) | No online/offline toggle or presence table; matching can pick a driver who isn't actually available. |

## 5. 🟡 Infrastructure / AWS / ops

| # | Gap | Notes | Type |
|---|---|---|---|
| I-1 | **Not deployed; alarms unproven** | The security-event CloudWatch alarms (auth/authz/rate-limit/payment failures) `synth` correctly but have never fired against a real App Runner log group. | true gap |
| I-2 | **No WAF** in front of the API | No managed rules / IP reputation / bot control at the edge. | scope decision (cost) |
| I-3 | **No CDN/edge in front of the API** | CloudFront fronts the assets bucket only, not App Runner. | scope decision |
| I-4 | **No S3 access logging** | Buckets are private + encrypted + TLS-only, but access isn't logged. | scope decision |
| I-5 | **No App Runner `MaxSize` cap** | The AWS Budget alarm is the only cost backstop; no hard instance ceiling. | true gap (cheap) |
| I-6 | **`deepmerge-ts` advisory in the production dep tree** | Via `@prisma/client` → `prisma` CLI → `@prisma/config`. Not runtime-reachable with untrusted input, but ships in the image. Fix with a Prisma bump. Corrects an earlier report that called all `npm audit` highs dev-only. | true gap (low) |
| I-7 | **Stripe secret is a placeholder** | `sk_live_REPLACE_ME` by design; must be set post-deploy. | expected |
| I-8 | **Manual verifications outstanding** | Google Maps API key restriction (Cloud Console), GitHub `production` environment protection rules — neither verifiable from code. | manual |
| I-9 | **No RLS; authorization is app-layer only** | Every ownership check is in Express/Prisma code. Correct and tested, but there's no database-level defense-in-depth. | scope decision |
| I-10 | **No S3 upload quarantine / malware scanning** | Presigned uploads go straight to the bucket; no scan-before-serve step. MIME allow-list + per-user key prefix exist, but no content scanning. | scope decision |
| I-11 | **RDS is single-AZ** | `db.t4g.micro`, single-AZ. Deletion protection is now env-aware (protected in prod). Multi-AZ/HA is deferred. | scope decision |

## 6. 🟡 Security — remaining items (from the two security passes)

| # | Gap | Notes |
|---|---|---|
| S-1 | **WebSocket token in the URL query string** | `wss://…/ws?token=…`. Works for browser WS clients but risks capture in proxy/access logs; also no re-validation once a socket outlives the 1-hour token. |
| S-2 | **No end-to-end auth-failure alerting proven** | See I-1 — the alarms exist but are unverified against a live deployment. |
| S-3 | **Cognito advanced security not enabled** | Adaptive/risk-based auth (brute-force/credential-stuffing) is Cognito console config, not set in `auth-stack.ts`. |

*(The exploitable issues found earlier — trip-status BOLA, payout `driverId` confusion, upload MIME/ownership, boot-blocking YAML, client-supplied fare — are all fixed and regression-tested.)*

## 7. 🔵 Testing

| # | Gap | Notes |
|---|---|---|
| T-1 | **No Flutter↔backend integration / E2E tests** | Can't exist until B-1/B-2 do. Today: backend has 115 API tests; Flutter has widget tests only (user_app 10, driver_app 5, admin_app 7). |
| T-2 | **No load/performance tests** | Nothing exercises concurrency, matching under load, or webhook storms beyond unit-level idempotency. |
| T-3 | **Docker image build unverified here** | The Docker daemon is unavailable in this environment; the production image has not been built this session. |

## 8. 🔵 Docs hygiene

- `TODO.md` is stale and partly wrong (payout "not started"); it should be reconciled with this register and the three audit reports (`SECURITY-AUDIT.md`, `SECURITY-HARDENING.md`, `PAYMENT-READINESS.md`).

---

## Priority order to make RavelGo actually work end-to-end

1. **B-3** deploy the backend to a real AWS account (reachable API + Cognito + RDS).
2. **B-2** wire Cognito auth in Flutter (get a real access token).
3. **B-1** add the Flutter API client and replace mock stores with real calls, app by app.
4. **B-4 + P-1/P-5** integrate Stripe (publishable key + PaymentSheet), decide the card-confirm flow, enable wallet top-up.
5. **P-4** Stripe Connect for real driver payouts; **P-2/P-3** failed-card retry + refunds.
6. **A-1** notifications (backend + push); then the remaining A-/R-/I- items by need.
7. Harden for scale (R-1/R-2 shared stores) and ops (I-1/I-5, WAF) before real traffic.

**What's genuinely solid today:** backend domain logic — fare/VAT/commission/payout math, wallet ledger with atomic debit and idempotent top-up crediting, authentication *verification* and role/ownership authorization, input validation, the Stripe *webhook* contract, and the CDK stack definitions. The gap is almost entirely *connection and deployment*, not core backend correctness.
