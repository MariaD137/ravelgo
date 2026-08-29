# RavelGo — Payment System & Flutter End-to-End Readiness

**Date:** 2026-08-29
**Question answered:** Can a real rider in `user_app` select a payment method, top up / pay, complete a ride payment, and have the backend correctly account for the money and driver commission — end to end?
**Method:** call chains traced through actual code; backend suite, lint, typecheck, build, `npm audit`, `cdk synth`, and Flutter `analyze`/`test` for all three apps actually run (results below). Money math verified with a concrete numeric trace, not by reading alone.

---

## RAVELGO PAYMENT READINESS

### Overall Verdict

# 🔴 NOT READY (to accept real rider payments end-to-end)

The **backend wallet path is genuinely complete and verified**; the **card path has a real backend gap**; and the **Flutter apps have no payment integration at all** — no HTTP client, no Stripe SDK, no authentication, no `/api` calls. A rider in `user_app` cannot today reach any real payment. This verdict is about the whole chain; the backend on its own is further along (see the split readiness in §"End-to-End Readiness").

### Payment Architecture (as actually wired today)

```
Rider (user_app)          ← chooses a payment LABEL only; no network layer exists
   ↓  ✗ NO CONNECTION (no http client, no Stripe SDK, no Cognito token)
RavelGo API               ← real, authenticated, tested
   ↓
Stripe / Wallet
   • WALLET: server-side atomic debit of a Stripe-funded balance ........ COMPLETE
   • CARD:   PaymentIntent created, but clientSecret has no path to rider  PARTIAL
   ↓
Payment ledger (Payment + WalletTransaction) ........................... COMPLETE
   ↓
25% commission on tax-inclusive total .................................. COMPLETE (verified)
   ↓
75% driver payout (period-based) ...................................... COMPLETE (verified)
```

### Implemented (CODE EXISTS → CALLER → USER-REACHABLE → ENDPOINT → AUTHZ → VALIDATED → STATE → SERVER-AUTHORITATIVE → TEST → PASSES)

| Capability | Backend | Reachable by a real rider today | Test |
|---|---|---|---|
| Wallet balance (`GET /wallet/me`) | ✅ auth'd, own-wallet only, backend-authoritative | ❌ no Flutter caller | ✅ |
| Wallet history (`GET /wallet/transactions`) | ✅ | ❌ | ✅ (via flows) |
| Wallet top-up (`POST /wallet/topup`) | ✅ real Stripe PaymentIntent, credited only on signed webhook, idempotent | ❌ | ✅ |
| Wallet ride payment | ✅ atomic debit, insufficient-funds → 402, no double-spend | ❌ | ✅ |
| Card charge (`POST /trips/:id/charge`) | ⚠️ PaymentIntent created; **clientSecret returned to the driver, not deliverable to the rider** | ❌ | ✅ (creation only) |
| Signed Stripe webhook | ✅ signature-verified, branches wallet vs trip, idempotent | n/a | ✅ |
| Server-authoritative fare + 7.5% VAT | ✅ computed server-side; client value ignored | ❌ (no Flutter caller) | ✅ |
| 25% commission / 75% payout | ✅ on tax-inclusive total, exact | ❌ | ✅ |
| Cash removed from rider payment options | ✅ API rejects CASH; ✅ **Flutter no longer offers Cash** (this pass) | ✅ (UI only) | ✅ backend |

**Verified money trace** (seed rule 500 + 120/km + 25/min, an 8.4 km / 22 min trip):
subtotal 2058 → VAT 154.35 → total **2212.35** → Stripe **221235 cents** → commission **553.09** + driver **1659.26** = **2212.35**. Tax applied exactly once; commission + driver share = total; no float drift.

### Missing (every broken link in the chain)

1. **The entire Flutter → backend connection.** None of the three apps declare `http`, `dio`, `flutter_stripe`, or any Cognito/Amplify dependency. The only network call in any app (`FindRoute.dart`) hits the Google Maps Places API, not RavelGo. There is no API client, no auth-token acquisition, and no Stripe SDK. **This is the primary blocker** and it blocks every payment capability above from being reachable.
2. **Card `clientSecret` has no delivery path to the rider.** `POST /trips/:id/charge` is `Driver`/`Admin`-only, and the CARD branch returns the `clientSecret` in the *driver's* HTTP response. Nothing hands it to the rider's device to confirm a PaymentSheet. Wallet avoids this (pure server debit); card cannot complete without either (a) a rider-initiated confirm step, or (b) an off-session saved-card charge — neither exists.
3. **No retry path for a failed card payment.** A `Payment` row is unique per `tripId`; once it exists (even `FAILED`), a re-charge returns 409 "already charged". A card decline therefore permanently blocks charging that trip.
4. **`REFUNDED` is an enum value with no backend transition.** There is no refund endpoint; the admin app's "refund" is local-state only. Nothing can legitimately move a payment to `REFUNDED`.
5. **Flutter wallet UI does not exist** (no balance screen, top-up, history, insufficient-balance state) — and was **not** built in this pass because it cannot be made real: a genuine backend-backed balance requires the missing HTTP client *and* a real Cognito access token, neither of which exists. A local/fake balance is explicitly disallowed, so none was added.

### Security Findings

**Critical:** none.

**High**
- **Card payment flow is incomplete end-to-end (completeness, not exploit).** See Missing #2 — no path exists to complete a real card charge; only wallet can settle today.

**Medium**
- **Failed-card retry is blocked** (Missing #3) — a decline strands the trip's payment permanently.
- **`npm audit` correction to the prior report.** 5 highs total. **3 are in the *production* dependency tree**, not dev-only as the earlier `SECURITY-AUDIT.md`/`SECURITY-HARDENING.md` stated: `@prisma/client` depends on the `prisma` CLI, which pulls `@prisma/config` → `deepmerge-ts` (recursive-merge stack-exhaustion advisory). It is **not reachable with untrusted input at API runtime** (config-load code, not the query path), but it does ship in the image. The other 2 (`js-yaml@4.3.0` under eslint, `brace-expansion`) are genuinely dev-only. Fix by bumping Prisma during maintenance; do not blind-upgrade.

**Low**
- Monetary columns (`Trip.estimatedFare/finalFare`, `Payment.amount`) are SQL `Float`. Rounding is applied at every computation so there is no observed drift at MVP scale, but integer minor units would be the stronger long-term representation. The wallet balance already uses integer cents.

**Verified secure (traced, not assumed):** wallet endpoints are auth'd and own-wallet-only (keyed on the caller's `cognitoSub` → `User.id`, no id in the path to tamper with); charge is ownership-checked (a driver not on the trip → 403); fare and VAT are server-computed and a client-supplied fare is ignored; the Stripe webhook is signature-verified and idempotent (duplicate top-up delivery does not double-credit — tested); wallet debit is atomic (guarded `updateMany`, no double-spend); no `sk_`/webhook-secret/AWS/DB credential appears in any Flutter source or `.env.example`.

### Flutter Findings

```
App:              user_app
Screen:           Ride request / SelectRide, PaymentView, SearchDriverScreen, FindDriverScreen, WorkProfileView
File:             views/TexiModule/SelectRide.dart, views/OtherViews/PaymentView.dart,
                  views/TexiModule/SearchDriverScreen.dart, views/TexiModule/FindDriverScreen.dart,
                  views/OtherViews/WorkProfileView.dart
Current behavior (before this pass): "Cash" was the default and an offered rider payment option.
Expected behavior: Cash must never appear as a rider payment option (backend rejects CASH).
Fix required: DONE this pass — rider payment options are now Card / RavelGo Wallet; no Cash anywhere
              rider-facing. (Pure local-state UI change; not wired to the backend — see below.)
```

```
App:              user_app (and driver_app, admin_app)
Screen:           all payment/wallet screens
File:             pubspec.yaml (no http/dio/flutter_stripe/cognito), whole lib/ tree
Current behavior: every payment, wallet, card, and fare value is LOCAL MOCK STATE.
Expected behavior: balances/fares/payments must originate from the backend.
Fix required: build an API client + Cognito auth + Stripe SDK integration. NOT done this pass —
              it depends on a reachable backend and real Cognito credentials that do not exist in
              this environment. A fake local wallet would violate the "must not be fake/local" rule,
              so none was built. This is the main end-to-end blocker.
```

### Backend Tests

```
npm test:            115 / 115 passing
npm run lint:        PASS (0 errors, 0 warnings)
npx tsc --noEmit:    PASS
npm run build:       PASS
npm audit --high:    5 high — 3 in production tree (Prisma config chain; not runtime-reachable
                     with untrusted input), 2 dev-only. See Medium finding above.
```
Payment-specific coverage present and passing: CARD accepted; WALLET accepted (funded debit); CASH rejected; VAT calc; 25% commission calc; fare-manipulation blocked; wallet top-up; webhook credit; duplicate webhook (no double-credit); wallet debit; insufficient balance (402); duplicate/second charge (409); unauthorized charge (403); cross-driver charge (403); payout calculation.

### Flutter Tests

```
user_app   — flutter analyze: PASS (0 errors; 157 pre-existing style infos/warnings, none new)
             flutter test:    10 / 10 passing
driver_app — flutter analyze: PASS (0 errors; 9 issues)
             flutter test:     5 / 5 passing
admin_app  — flutter analyze: PASS (0 errors; 10 issues)
             flutter test:     7 / 7 passing
Flutter SDK: available (stable). Runs were real, not fabricated.
```

### AWS Tests

```
cdk synth (all stacks): PASS
Docker build:           NOT RUN — the Docker daemon is unavailable in this environment
                        (CLI only). The image was not built.
Deployed AWS:           NONE — no account is wired into this repo; nothing verified against
                        a running App Runner / RDS / Stripe live account.
```

### Payment State Machine

`PaymentStatus` enum: `PENDING, SUCCEEDED, FAILED, REFUNDED` (there is no `PROCESSING` on payments — that value lives on `PayoutStatus`).

| State | Who sets it | Valid transition | Flutter behavior |
|---|---|---|---|
| PENDING | Driver/Admin charge (CARD) creates it | → SUCCEEDED / FAILED via signed webhook | none (no integration) |
| SUCCEEDED | Webhook (CARD) or immediate on WALLET debit | terminal | none |
| FAILED | Webhook (CARD failure) | terminal — **no retry path** (row blocks re-charge) | none |
| REFUNDED | **nothing** — enum value with no endpoint | — | none |

Illegal-transition checks (backend, tested unless noted): pay twice / already-paid → 409; another rider's trip → charge is driver-scoped, unrelated driver → 403; cancelled/not-completed trip → 409; insufficient wallet → 402; retry failed card → **blocked (gap, Missing #3)**; refresh/kill app mid-payment → N/A (no app integration; but wallet credit is webhook-idempotent and card status is webhook-driven, so the backend is safe against duplicate delivery).

### End-to-End Readiness (split)

| Layer | Status |
|---|---|
| **Backend — wallet** | ✅ Ready for staging: complete, authoritative, idempotent, tested. |
| **Backend — card** | ⚠️ Partial: PaymentIntent creation works; clientSecret delivery to the rider and failed-retry are unsolved. |
| **Stripe** | ⚠️ Server integration correct (PaymentIntent + signed webhook). No publishable key/PaymentSheet in Flutter; infra Stripe secret is still a placeholder. |
| **Wallet** | ✅ Backend complete/tested; ❌ no Flutter UI. |
| **Flutter** | 🔴 Not ready: zero backend/auth/Stripe integration; all payment state is mock. |
| **AWS staging** | ⚠️ `synth`-valid; not deployed; Docker image not built here. |
| **Production** | 🔴 No. |

### Production Blockers (checklist)

- [ ] Build the Flutter API client + Cognito authentication (acquire a real access token) so any `/api` call — wallet included — can be made at all.
- [ ] Integrate `flutter_stripe` (publishable key only) + PaymentSheet, and define how the card `clientSecret` reaches the rider (rider-initiated confirm, or off-session saved-card charge). Resolve backend Missing #2 accordingly.
- [ ] Add a failed-card retry path (Missing #3).
- [ ] Build the rider wallet UI (balance / top-up / history / insufficient-balance / success / failure), backed only by the real endpoints — never a local balance.
- [ ] Decide and implement the refund path if `REFUNDED` is to be usable (Missing #4).
- [ ] Deploy to a real AWS account; set real Stripe keys (placeholders ship by design); build & push the Docker image (not possible here) and confirm a healthy boot.
- [ ] Bump Prisma to clear the `deepmerge-ts` production-tree advisory during maintenance.
- [ ] End-to-end test on a device against the deployed backend before calling any of this production-ready.

---

## What changed in this pass

Only one code change, and only the honest one available without fabricating backend connectivity: **Cash was removed as a rider-facing payment option in `user_app`** (SelectRide, PaymentView, the two driver-search fare rows, and the work-profile billing picker), replaced with **Card / RavelGo Wallet**. These are local-state UI selections today — they are *not* wired to the backend, and this report does not claim otherwise. No fake wallet balance or fake payment was added, per the explicit rule. Verified: `user_app` analyze clean (0 errors), 10/10 tests still pass.
