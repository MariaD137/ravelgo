# Driver approval flow — Driver App ↔ Admin App

This documents the *actual* implementation of driver onboarding approval as
traced through the code, the single source of truth for each state, and the
gaps that were closed. Read it before touching anything in this flow.

## Source of truth

| State the product talks about | Where it lives | Written by | Read by |
|---|---|---|---|
| Application under review | `Driver.status = PENDING_REVIEW` (default on create) | `POST /api/drivers/apply` | `GET /api/drivers/me`, `GET /api/drivers?status=` |
| Approved | `Driver.status = ACTIVE` | `PATCH /api/drivers/:id/status {status:"ACTIVE"}` (Admin, `drivers:write`) | same, plus `PATCH /api/drivers/me/availability` and `services/matching.ts` |
| Suspended | `Driver.status = SUSPENDED` | same endpoint with `SUSPENDED` | same |
| Rejected (driver-level) | **does not exist** — there is no `REJECTED` value in `DriverStatus` | — | — |
| Document approved / rejected (+ reason) | `DriverDocument.status`, `DriverDocument.rejectionReason` | `PATCH /api/documents/:id/review` | `GET /api/drivers/me`, `GET /api/documents/me`, `GET /api/drivers/:id` |
| Vehicle approval | **does not exist** — `Vehicle` has no status column | — | — |
| Eligible to go online | `Driver.status == ACTIVE` **only** | — | `PATCH /api/drivers/me/availability` (409 otherwise) |
| Matched to trips | `status == ACTIVE && isOnline && no active trip/delivery (&& vehicle class if the category restricts it)` | — | `services/matching.ts` |

`User.suspended` exists but is only consulted for **admins** (`isSuspendedAdmin`)
and riders; the driver-side block is `Driver.status = SUSPENDED`.

**Approving documents never changes `Driver.status`.** Approving the driver
never checks documents. They are two independent review records; the admin's
explicit "Approve driver" is the only thing that unlocks going online.

## The flow, file by file

```
Driver App
  DriverShell._loadProfile  (driver_app/lib/views/shell/driver_shell.dart)
    -> DriverApi.getMe                GET  /api/drivers/me        (drivers.routes.ts, requireRole Driver)
    -> on 404/403: DriverApi.provisionMe
                                      POST /api/drivers/apply     (any authed user; server adds Cognito "Driver" group)
       then AuthService.refreshTokens (forced REFRESH_TOKEN_AUTH so the new group is on the access token)
  MyDocumentsScreen -> DriverApi.uploadDocument
    -> POST /api/uploads/presign  -> PUT to S3 (documents bucket)
    -> POST /api/documents  {title, fileKey}   -> DriverDocument(status=PENDING)

Backend (Postgres via Prisma)
  Driver { status: PENDING_REVIEW }   DriverDocument { status: PENDING }

Admin App
  DashboardScreen "Pending driver applications"  <- GET /api/admin/dashboard .pendingDriverApplications
  DriverListScreen (status chip)                  <- GET /api/drivers?status=PENDING_REVIEW&pageSize=100
  DriverDetailScreen                              <- GET /api/drivers/:id  (user + documents)
    view document  -> GET /api/drivers/:id/documents/:docId/url   (signed S3 URL, 300 s, audited)
    approve/reject document -> PATCH /api/documents/:id/review {status, rejectionReason?}
    APPROVE DRIVER  -> AdminApi.setDriverStatus -> PATCH /api/drivers/:id/status {status:"ACTIVE"}

Backend PATCH /api/drivers/:id/status (drivers.routes.ts)
  requireAuth (Cognito access-token JWT) -> requireAdminPermission("drivers:write")
    (Cognito "Admin" group AND User.adminRole ∈ {SUPER_ADMIN, OPERATIONS_MANAGER} AND not suspended)
  findUnique driver -> 404 if missing
  same status already -> 200, no-op (idempotent, no duplicate notification)
  prisma.driver.update({status})
  recordAudit DRIVER_STATUS_CHANGED {from, status}   (awaited)
  notifyUser(driver.userId, DRIVER_ACCOUNT_STATUS_CHANGED, "You're approved!")
    -> Notification row  +  AWS Pinpoint push to every PushToken (best-effort)
  -> 200 Driver

Driver App learns the new state (the notification is only a prompt to re-fetch)
  - pull-to-refresh on Home                               -> GET /api/drivers/me
  - app resumed from background                           -> GET /api/drivers/me
  - poll every 30 s while not ACTIVE (2 min once ACTIVE)  -> GET /api/drivers/me
  - in-app notification tap / push tap / push in foreground with type
    DRIVER_ACCOUNT_STATUS_CHANGED -> DriverProfileEvents.requestRefresh() -> GET /api/drivers/me
  - returning from the Notifications screen               -> GET /api/drivers/me
  status == ACTIVE -> online toggle shown -> PATCH /api/drivers/me/availability {isOnline:true}
```

## Gaps found and their status

| Area | Was | Problem | Severity | Now |
|---|---|---|---|---|
| Driver status refresh | Profile fetched once in `initState`; never again | Approval only visible after a full app restart; on mobile, backgrounding/resuming did not refresh | CRITICAL | Refresh on resume, poll while pending, pull-to-refresh, refresh on notification/push, refresh after Notifications screen |
| Driver UI fallback state | `DriverProfile()` default `status = "PENDING_REVIEW"`; any failed `GET /drivers/me` silently rendered "Application under review" | UI fabricated a review state on 403/404/network error | CRITICAL | Default status is `""`; explicit loading / error / pending / suspended states; tests pin this |
| Token vs Cognito group | `POST /drivers/apply` adds the Driver group server-side but the app kept its pre-grant access token (valid ≤ 1 h) | Every Driver-only route (profile, **document upload**, vehicles) 403'd for up to an hour after applying; a 403 rendered as "under review" | HIGH | `AuthService.refreshTokens()` forces a refresh after apply; `getMe` is tried first so existing drivers no longer re-apply on every launch |
| Admin pending queue | Client-side filter over first 100 of *all* drivers | PENDING_REVIEW drivers beyond page 1 invisible | HIGH | `GET /drivers?status=` server-side filter; list reloads per chip |
| Admin dashboard | "Pending approvals" = pending documents + Car Paddy, but the tile opened the PENDING_REVIEW driver list | Count and list disagreed; a pending applicant with all documents approved showed as 0 | HIGH | New `pendingDriverApplications` field; tile renamed and bound to it (`pendingApprovals` retained) |
| Document approval vs driver approval | Independent records; UI text implied document approval unlocks going online | Reviewers approve every document and assume the driver is approved; the driver stays PENDING_REVIEW | HIGH (workflow) | Admin detail shows a hint while PENDING_REVIEW and a confirmation listing unapproved documents before "Approve driver"; driver card shows real per-document state |
| Approval endpoint | `prisma.driver.update` straight from params; audit fire-and-forget; re-approval re-notified | Nonexistent id → generic Prisma 404; duplicate/stale approve spammed "You're approved!"; no `from` in audit | MEDIUM | Explicit 404, idempotent no-op on same status, audit awaited with `from` |
| Android driver APK env | `API_BASE_URL` hardcoded in `android-build.yml`; Cognito IDs from separate secrets; admin web read stack outputs | Driver APK and admin console could silently target different backends / user pools (exactly "approval doesn't reach the driver") | HIGH (needs AWS verification) | Workflow now reads `ServiceUrl`, `UserPoolId`, `UserPoolClientId` from the staging stacks via the same OIDC role as `staging-deploy.yml`, and fails loudly if it can't |
| Push for driver builds | CI wrote `PINPOINT_APPLICATION_ID` / `PUSH_IDENTITY_POOL_ID` for `user_app` only | Driver APK never registered a device token → no approval push | MEDIUM | Written for both apps (still a safe no-op when unset; polling covers the gap) |
| Push/in-app tap handling | `DRIVER_ACCOUNT_STATUS_CHANGED` has no reference → tap did nothing | Notification promised a refresh that never happened | MEDIUM | Tap and foreground receipt trigger a profile re-fetch; the notification never sets state itself |
| Driver-level rejection | No `REJECTED` in `DriverStatus` | Admin "rejects" only per document or by SUSPENDED; a driver is never told their *application* was rejected | MEDIUM | **Not changed** (schema/product decision) — see below |
| Vehicle approval | No status on `Vehicle` | Cannot be part of eligibility | LOW | **Not changed** — documented |
| Authorization | Admin group + `drivers:write` preset + not-suspended; driver routes cannot set status | — | PASS (tested: self, other driver, rider, anonymous, SUPPORT_AGENT all refused; client `status` fields ignored) | — |
| Transactions | Single-row update; audit and notification are deliberately best-effort | Acceptable for one row | PASS | — |
| Environment (web) | Both web apps built from the same stack outputs | — | PASS | — |

## Still open (product / infrastructure decisions)

1. **Driver-level rejection state.** If the business needs "application
   rejected" (as opposed to "a document was rejected, re-upload it"), add
   `REJECTED` to `DriverStatus` with a migration, a reason column, a message
   in `DRIVER_STATUS_MESSAGES`, and a Driver App branch. Not invented here.
2. **Should approval require approved documents?** The backend intentionally
   leaves this to the reviewer. If it must be enforced, add the check in
   `PATCH /drivers/:id/status` (server-side, never only in the Admin App).
3. **Verify staging outputs match the previously hardcoded App Runner URL.**
   `android-build.yml` now needs `vars.AWS_STAGING_DEPLOY_ROLE_ARN` /
   `vars.AWS_REGION` (already used by `staging-deploy.yml`). Confirm the first
   run's discovered `ServiceUrl` is the backend the admin console uses.
4. **Push delivery** requires `PINPOINT_APPLICATION_ID` on the backend and
   the two push secrets in CI; until then the driver app converges by polling.
5. `POST /drivers/apply` sets `User.role = DRIVER` on an existing user. An
   admin account opening the Driver App would have its role flipped. Now only
   reachable when `GET /drivers/me` is 403/404, but still worth guarding.
