# RavelGo — Admin Access Recovery

**Status:** Discovery complete, commands prepared. **No accounts have been created, no admin has been deactivated, and no AWS/Cognito credentials have been used or requested by this session.** Everything below is a runbook for you (or another verified operator with real AWS access) to execute yourselves.

**Scope note:** this document covers Cognito group membership + the RavelGo Postgres `User`/admin-role model only. It does not touch unrelated data, does not reset the database, and does not create a new auth system.

---

## Root Cause (of the original lockout)

RavelGo's admin authorization is **Cognito + database**, not either alone:

1. **Authentication (Cognito):** `admin_app` signs in against a Cognito User Pool (`infra/lib/auth-stack.ts`). A successful sign-in returns a JWT whose `cognito:groups` claim lists the pool groups the user belongs to (`Rider` / `Driver` / `Admin`).
2. **Authorization (backend):** `backend/src/middleware/auth.ts`'s `requireAuth` verifies that JWT (`CognitoJwtVerifier`, `tokenUse: "access"`) and populates `req.user = {sub, email, groups}` from the verified token only. `requireRole("Admin")` checks `groups.includes("Admin")`.
3. **Fine-grained authorization (backend + database):** `backend/src/lib/admin-permissions.ts`'s `requireAdminPermission(permission)` additionally requires: not suspended (`User.suspended` in Postgres) → MFA enrolled (checked live against Cognito) → the caller's `AdminRole` preset (`User.adminRole`: `SUPER_ADMIN` / `OPERATIONS_MANAGER` / `SUPPORT_AGENT` / `FINANCE_VIEWER`) grants that specific permission.
4. **Known loophole (still open, not fixed by this document):** `effectiveAdminRole()` treats an Admin-group Cognito user with **no** Postgres `User` row — or a row with `adminRole: null` — as full `SUPER_ADMIN` by default. This keeps pre-existing admin accounts working, but means Cognito group membership alone is functionally SUPER_ADMIN unless a restricted row exists. Flagging this so any new admin row is created deliberately.

**Why the Admin App was unreachable — now resolved:** staging's App Runner service (`ravelgo-backend-staging`) had been deleted out-of-band and its CloudFormation tracking had drifted, so every deploy failed and the API was unreachable (`ERR_NAME_NOT_RESOLVED` / connection failures) regardless of any individual account's status. This was diagnosed and fixed in this session — the service has been recreated, confirmed `RUNNING`, and the staging web apps have been successfully rebuilt and republished against it. If admin login is still failing after this, it's now a genuine account-specific issue, not an infrastructure one — check the account directly:

```bash
export ENVNAME=staging   # confirm this is the environment you actually use
POOL="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)"
aws cognito-idp admin-get-user --user-pool-id "$POOL" --username you@example.com
aws cognito-idp admin-list-groups-for-user --user-pool-id "$POOL" --username you@example.com
```

---

## Existing Superuser(s)

Not identified from this session — no database/AWS access here. To see who currently holds `ADMIN`/`SUPER_ADMIN`:
```sql
select id, email, "adminRole", suspended, "cognitoSub" from "User" where role = 'ADMIN';
```
or, once any working SUPER_ADMIN session exists, `GET /api/admin-users` from the app itself.

**Not deactivated.** Nothing is removed until the replacement accounts are created and independently verified working — see "Deactivation" below.

---

## New Super Admins — how to create them (not yet done)

**⚠️ Confirm the exact email spelling first** — `mtabiowo57@gmail.com` vs `matabiowo57@gmail.com` were both used across this conversation. Only proceed with the address you've verified is correct.

### Preferred: through the app itself (fully audited, no raw Cognito calls)

Requires an existing, working `SUPER_ADMIN` session (now that staging is reachable again, whoever already has legitimate access can use this). This is the Admin App's own "Invite admin" mechanism — `POST /api/admin-users` (`backend/src/routes/admin-users.routes.ts`):

```bash
curl -X POST "https://<current-staging-api-url>/api/admin-users" \
  -H "Authorization: Bearer <your admin access token>" \
  -H "Content-Type: application/json" \
  -d '{"email":"<verified-email-1>","firstName":"<first>","lastName":"<last>","adminRole":"SUPER_ADMIN"}'
# repeat for the second email
```

This single call: creates the Cognito user via `AdminCreateUser` (Cognito auto-generates and emails a temporary password — this command never sees, stores, or logs it), adds them to the `Admin` group, creates the linked Postgres `User` row with `adminRole: "SUPER_ADMIN"` in the same request, and writes an `ADMIN_USER_CREATED` audit log entry. The caller's own admin session must have MFA enrolled, or this call is rejected server-side.

### Fallback: direct Cognito bootstrap (only if no admin session is reachable at all)

```bash
export ENVNAME=staging   # confirm this is correct first
POOL="$(aws cloudformation describe-stacks --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)"

for EMAIL in <verified-email-1> <verified-email-2>; do
  aws cognito-idp admin-create-user \
    --user-pool-id "$POOL" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --desired-delivery-mediums EMAIL
  # Cognito generates and emails a one-time temporary password itself
  # (FORCE_CHANGE_PASSWORD state) — never printed, stored, or logged here.

  aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$POOL" --username "$EMAIL" --group-name Admin
done
```

`infra/lambda/post-confirmation/index.mjs` only fires on a genuine self-service sign-up confirmation, so this path will not accidentally add either account to `Rider`.

This fallback does **not** create the Postgres `User` row — per the loophole above, the account would default to full `SUPER_ADMIN` via `effectiveAdminRole()`'s no-row fallback, but would be invisible in the Admin Users management screen and un-suspendable through it. Don't leave it in that state: once the account has a working session, immediately give it a real row via `PATCH /admin-users/:id/role`, or a direct insert matching the current `User` table schema (verify columns against `backend/prisma/schema.prisma` before running — do not copy-paste blind).

---

## Password Security

Neither path generates, stores, prints, or commits a password anywhere. Both rely on Cognito's own `AdminCreateUser` temporary-password mechanism (Cognito generates and emails it directly; the account is `FORCE_CHANGE_PASSWORD` until the user sets their own on first sign-in) — confirmed in `backend/src/services/cognito.ts#createAdminUser`.

## Password Reset

Already supported, unmodified: `POST /admin-users/:id/password-reset` (`requireAdminPermission("manage_admins")`) triggers Cognito's `AdminResetUserPasswordCommand` — same mechanism as self-service "Forgot password?". Never returns or logs a password.

## MFA

TOTP only (`infra/lib/auth-stack.ts`), Cognito pool-level setting is `Mfa.OPTIONAL` — enforcement is at the application layer: enrollment is required server-side before any mutating admin action succeeds (`isAdminMfaEnrolled()` in `admin-permissions.ts`); a new admin can sign in and view their own profile immediately but can't do anything else until TOTP setup is complete. No MFA secret is stored in RavelGo's own code or database — it lives entirely in Cognito.

## Database

`User.cognitoSub` is the join key between Cognito and Postgres, unique, set once, never client-writable. The "preferred" creation path keeps both in sync atomically in one request; the "fallback" path does not (see loophole caveat) — don't leave it in that state longer than necessary.

## Security (verified in code, not yet re-tested against live new accounts)

- **Self-promotion is impossible:** nothing lets a caller set their own `adminRole`; the only writer is `PATCH /admin-users/:id/role`, itself gated by `requireAdminPermission("manage_admins")` (SUPER_ADMIN only) and blocked from demoting the last SUPER_ADMIN.
- **`req.user` is server-derived only** — from the verified JWT, never from request body/headers.
- **Every admin-mutating route is gated**, not just `/admin-users`.

## Remaining Problems

1. Staging backend is now confirmed working (this session fixed the App Runner drift and redeployed) — the infrastructure blocker from the earlier discovery pass is resolved.
2. **The replacement accounts have not been created** — commands above are prepared, not run. Requires a verified operator with real AWS credentials.
3. **The old superuser(s) have not been touched.** Do this only after the replacement accounts are created and independently confirmed working (login + MFA + a real admin action succeeds).
4. **The email address for one target account is ambiguous** (`mtabiowo57@gmail.com` vs `matabiowo57@gmail.com`) — resolve before running anything.
5. Finding: the no-row-defaults-to-SUPER_ADMIN loophole (see Root Cause #4) is still open — worth closing in a follow-up so future admin provisioning can't silently over-grant.
