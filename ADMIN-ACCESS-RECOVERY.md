# RavelGo — Admin Access Recovery

**Status:** Discovery complete. New-admin creation and old-superuser deactivation are **not yet performed** — this session has no AWS/Cognito credentials, so the steps below are a runbook for you to execute with your own AWS CLI access, not a record of changes already made.

**Scope note:** this document covers Cognito group membership + the RavelGo Postgres `User`/admin-role model only. It does not touch the database, does not reset anything, and does not create a new auth system.

---

## Root Cause

RavelGo's admin authorization is **Cognito + database**, not either alone:

1. **Authentication (Cognito):** `admin_app` signs in against a Cognito User Pool (`infra/lib/auth-stack.ts`). A successful sign-in returns a JWT whose `cognito:groups` claim lists the pool groups the user belongs to (`Rider` / `Driver` / `Admin` — see `scripts/set-role.sh`, `infra/lambda/post-confirmation/index.mjs`).
2. **Authorization (backend):** `backend/src/middleware/auth.ts`'s `requireAuth` verifies that JWT (`CognitoJwtVerifier`, `tokenUse: "access"`) and populates `req.user = {sub, email, groups}` from the verified token — never from client input. `requireRole("Admin")` checks `groups.includes("Admin")`.
3. **Fine-grained authorization (backend + database):** `backend/src/lib/admin-permissions.ts`'s `requireAdminPermission(permission)` — used on every mutating admin route — additionally requires: not suspended (`User.suspended` in Postgres) → **MFA enrolled** (live Cognito check, enforced server-side as of this session's security fix) → the caller's `AdminRole` preset (`User.adminRole` in Postgres: `SUPER_ADMIN` / `OPERATIONS_MANAGER` / `SUPPORT_AGENT` / `FINANCE_VIEWER`) grants that specific permission.
4. **The loophole worth knowing about (Finding 1 of this session's security audit, still open):** `effectiveAdminRole()` treats an Admin-group Cognito user with **no** Postgres `User` row — or a row with `adminRole: null` — as full `SUPER_ADMIN` by default. This exists so admin accounts created before the role-preset system shipped keep working, but it also means Cognito group membership alone is functionally SUPER_ADMIN unless a restricted row exists. This document does not fix that finding; it's flagged so any new admin row is created deliberately rather than relying on this default.

**Why your account can't currently get in — what I can and can't confirm from this sandbox:**

This session has no AWS credentials at all (no `aws` CLI, no Cognito/RDS access) — everything below is what I can rule in/out from the *code*, not from your live environment.

What I can confirm from earlier in this session: **staging's backend (App Runner) is stuck in a deploy-rollback loop.** Four consecutive deploys tonight (including two carrying no admin-related changes at all) failed identically at the same ~65-second mark, ending `ROLLBACK_IN_PROGRESS`, with staging still serving an old image. If your login attempts go through the staging API, a backend that's unhealthy or serving stale code would produce exactly the generic "Could not verify your admin account" symptom you described earlier tonight — independent of anything about your specific Cognito account. I could not pull the App Runner service's own CloudWatch logs to find *why* it fails health checks — the CI role's `logs:FilterLogEvents` permission was never granted (needs `cd infra && npm run bootstrap-ci-staging`, from your machine).

What I could **not** rule in/out (needs your AWS CLI, not available here):
- Your specific Cognito account's status (`CONFIRMED` vs disabled vs `FORCE_CHANGE_PASSWORD`)
- Whether your account is actually in the `Admin` group
- Whether your Postgres `User.suspended` flag is set
- Whether you're pointed at the right user pool/environment (staging vs production have separate pools)
- Your MFA enrollment status (now required server-side for any *mutating* admin action, per this session's Finding 2 fix — read-only routes like your own profile are unaffected)

**To check your own account directly** (replace `you@example.com`, run once you have AWS CLI access):
```bash
export ENVNAME=staging   # or production — confirm which one you actually use before running anything below
POOL="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)"
aws cognito-idp admin-get-user --user-pool-id "$POOL" --username you@example.com
aws cognito-idp admin-list-groups-for-user --user-pool-id "$POOL" --username you@example.com
```

---

## Existing Superuser

**Not identified from this session** — I have no AWS/database access to look it up. Run the commands above against your own email (and against the local admin username you normally use, if different) to see its Cognito status/groups. To see its RavelGo-side role, ask an already-authenticated SUPER_ADMIN to check `GET /api/admin-users`, or query Postgres directly:
```sql
select id, email, "adminRole", suspended, "cognitoSub" from "User" where role = 'ADMIN';
```

**Not deactivated.** Per your instruction, nothing is removed until the three new accounts are created and verified. See "Deactivation" at the end.

---

## New Super Admins — how to create them (not yet done)

Two ways to do this, in order of preference.

### Preferred: through the app itself (fully audited, no raw Cognito calls needed)

If you can get **any** working `SUPER_ADMIN` session (your own account, once you confirm it's healthy via the commands above, and once staging's backend is actually reachable) — the correct, already-built mechanism is `POST /api/admin-users` (`backend/src/routes/admin-users.routes.ts`), same as the Admin App's own "Invite admin" screen. For each of the three emails:

```bash
curl -X POST "https://<your-api-url>/api/admin-users" \
  -H "Authorization: Bearer <your admin access token>" \
  -H "Content-Type: application/json" \
  -d '{"email":"lacadiagroup@gmail.com","firstName":"<first>","lastName":"<last>","adminRole":"SUPER_ADMIN"}'
# repeat with nosagrant@protonmail.com and matabiowo57@gmail.com
```

This single call: creates the Cognito user via `AdminCreateUser` (Cognito auto-generates and *emails* a temporary password — nothing here ever sees, stores, or logs it), adds them to the `Admin` group, creates the linked Postgres `User` row with `adminRole: "SUPER_ADMIN"`, and writes an `ADMIN_USER_CREATED` audit log entry. It also — since this session's Finding 2 fix — means *you* need MFA enrolled on your own admin session before this call will succeed (`requireAdminPermission("manage_admins")` now requires it).

### Fallback: direct Cognito bootstrap (only if no admin session is reachable at all)

```bash
export ENVNAME=staging   # confirm this is the right environment first
POOL="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)"

for EMAIL in lacadiagroup@gmail.com nosagrant@protonmail.com matabiowo57@gmail.com; do
  aws cognito-idp admin-create-user \
    --user-pool-id "$POOL" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --desired-delivery-mediums EMAIL
  # Cognito generates and emails a one-time temporary password itself (FORCE_CHANGE_PASSWORD
  # state) — this command never prints, stores, or logs that password.

  aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$POOL" --username "$EMAIL" --group-name Admin
done
```

Confirmed: `infra/lambda/post-confirmation/index.mjs` only fires (and only ever adds the `Rider` group) on `PostConfirmation_ConfirmSignUp` — i.e. a genuine self-service sign-up. Completing an admin-created account's forced password change does **not** trigger it, so this path will not accidentally add these three to `Rider`.

This fallback does **not** create the Postgres `User` row, so — per the "loophole" noted above — each account would default to full `SUPER_ADMIN` anyway via `effectiveAdminRole()`'s no-row fallback, but would be **invisible in the Admin Users management screen** and un-suspendable through it. Don't leave it there — once *any* one of the three (or you) has a working session, immediately follow up with a real row, either via the app's `PATCH /admin-users/:id/role` (if a row already exists from a prior partial attempt) or a direct, explicit insert:
```sql
insert into "User" (id, "cognitoSub", role, "adminRole", "firstName", "lastName", email, suspended, "createdAt")
values (gen_random_uuid(), '<the Cognito sub/username from admin-create-user's output>', 'ADMIN', 'SUPER_ADMIN', '<first>', '<last>', '<email>', false, now());
```
(Match this repo's actual `User` table columns/defaults — check `backend/prisma/schema.prisma` before running; the above is illustrative, not copy-paste-verified against a live schema.)

---

## Password Security

No password was generated, stored, printed, or committed by this session. Both paths above rely entirely on Cognito's own `AdminCreateUser` temporary-password mechanism — Cognito generates it, emails it directly to the user, and puts the account in `FORCE_CHANGE_PASSWORD` until they set their own permanent password on first sign-in. Nothing in RavelGo's own code or database ever sees that value (confirmed in `backend/src/services/cognito.ts#createAdminUser` and `admin-users.routes.ts`).

## Password Reset

Already supported and unmodified by this session: `POST /admin-users/:id/password-reset` (`requireAdminPermission("manage_admins")`) triggers Cognito's `AdminResetUserPasswordCommand` — the same underlying mechanism as self-service "Forgot password?", just admin-triggered. Never returns or logs a password or reset code (see the existing test `POST /api/admin-users/:id/password-reset triggers a Cognito reset and never returns a password`).

## MFA

TOTP only (`infra/lib/auth-stack.ts`: `mfaSecondFactor: {sms: false, otp: true}`), pool-wide setting is `Mfa.OPTIONAL` (not required at the Cognito level — open Finding 2 of the original audit, deliberately not changed here to avoid locking out existing admins without a coordinated rollout). As of this session's fix, **enrollment is required server-side** before any of `requireAdminPermission`'s gated mutating actions succeed (`isAdminMfaEnrolled()` in `admin-permissions.ts`) — a new admin can sign in and view their own profile immediately, but cannot invite/manage anything else until they complete TOTP setup (`admin_app`'s `MfaSetupScreen`, then `POST /admin-users/me/mfa-enrolled` records it in the audit log; Cognito itself remains the actual source of truth for whether MFA is on). No MFA secret is stored anywhere in RavelGo's own code or database — it lives entirely in Cognito.

## Database

`User.cognitoSub` is the join key between Cognito and Postgres — a unique column, set once at creation and never client-writable. The "preferred" creation path above keeps the two in sync atomically in one request. The "fallback" path does not, by design (see loophole caveat above) — do not leave it in that state longer than necessary.

## Security

Verified in code (not re-tested against a live environment, since none of the three accounts exist yet):
- **Self-promotion is impossible:** nothing in the codebase lets a caller set their own `adminRole`; the only writer is `PATCH /admin-users/:id/role`, itself gated by `requireAdminPermission("manage_admins")` (SUPER_ADMIN only) and blocked from demoting the last SUPER_ADMIN.
- **`req.user` is server-derived only:** populated exclusively from the verified JWT (`middleware/auth.ts`), never from request body/headers — a modified client-side "admin state" has no effect on any backend check.
- **Every admin-mutating route is gated**, not just the ones under `/admin-users` — this session's own test suite exercises 21 route files / 263+ tests authenticating as `Admin` against `requireAdminPermission`/`blockIfAdminLacksPermission`.

## Tests

Only pre-existing tests plus this session's already-shipped fixes were run — **no new tests target the three specific accounts above**, since they don't exist yet and this sandbox has no path to create or authenticate as them. What was run and passed earlier tonight, and remains valid evidence for the authorization claims above: the full backend suite (448 tests, one known pre-existing unrelated flake), including the dedicated MFA-bypass and privilege-boundary tests added for Finding 2 (`admin-users.routes.test.ts`) — e.g. an Admin-group token with `mfaEnabled: false` is rejected from every `requireAdminPermission`-gated route; a caller without a SUPER_ADMIN preset is rejected from `POST /admin-users`. Once the three accounts exist for real, the "Testing" checklist from the original request (new admin can authenticate, is authorized, drivers/normal users are still rejected, invalid tokens are rejected, password reset works, MFA is enforced, Cognito/DB stay in sync) should be re-run against them specifically — that requires a live, reachable backend, which staging does not currently have.

## Remaining Problems

1. **Staging App Runner is stuck rolled back** (4/4 consecutive deploys tonight failed identically) — blocks reliably testing *any* admin login, old or new, against staging until resolved with AWS CLI access (`bootstrap-ci-staging`, then inspect `describe-service`/CloudWatch logs).
2. **The three accounts have not been created** — the commands above are prepared, not run.
3. **The old superuser has not been touched** — per your instruction, do this only after the three new accounts are verified working.
4. **This session cannot verify anything live** (no AWS/Cognito/production-DB credentials) — everything above is code-level analysis plus exact commands for you to run and verify yourself.
5. Finding 1 (the no-row-defaults-to-SUPER_ADMIN loophole) is still open — worth closing in a follow-up so future admin provisioning can't silently over-grant.
