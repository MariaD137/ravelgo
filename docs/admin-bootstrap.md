# Bootstrapping the first Admin user

There's no self-serve "sign up as Admin" flow, and there shouldn't be —
`RavelGo-Auth`'s Cognito User Pool has self sign-up enabled for riders and
drivers only in practice, since nothing in the app UI offers an Admin
sign-up path. A brand-new user who signs up isn't in any Cognito group at
all until someone puts them there, and every Admin-only route
(`requireRole("Admin")` in `backend/src/middleware/auth.ts`) checks the
`cognito:groups` claim on their access token. So the very first Admin has to
be created by hand, once, directly against Cognito.

This only needs doing once per environment (per user pool) — after the
first Admin exists, they can promote others from the admin app itself if
that gets built, or a second operator can just repeat the same CLI steps
below.

## Prerequisites

- The `RavelGo-Auth` CDK stack has been deployed (see `infra/README.md`).
- The AWS CLI is configured with credentials for that same AWS account
  (`aws configure` or `aws sso login`).
- The Cognito `UserPoolId` from the stack's output. If you don't have it
  handy:
  ```bash
  aws cognito-idp list-user-pools --max-results 20
  ```

## 1. Create the user

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example \
  --user-attributes Name=email,Value=admin@ravelgo.example Name=email_verified,Value=true \
    Name=given_name,Value=Admin Name=family_name,Value=User \
  --message-action SUPPRESS
```

`--message-action SUPPRESS` skips the invitation email — set a real
temporary password yourself instead:

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example \
  --password '<a-strong-temporary-password>' \
  --permanent
```

(`--permanent` avoids the "force change password" state, which the admin
app's login screen doesn't currently have a flow for. Have the admin change
it themselves once logged in, or repeat this command to rotate it.)

## 2. Put them in the Admin group

The `RavelGo-Auth` stack already creates `Rider`, `Driver`, and `Admin`
Cognito groups (see `infra/lib/auth-stack.ts`) — nothing to create, just
assign membership:

```bash
aws cognito-idp admin-add-user-to-group \
  --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example \
  --group-name Admin
```

## 3. Confirm it worked

```bash
aws cognito-idp admin-list-groups-for-user \
  --user-pool-id <UserPoolId> \
  --username admin@ravelgo.example
```

should list `Admin`. Signing in from the admin app now gets an access token
whose `cognito:groups` claim includes `"Admin"`, which is all
`requireRole("Admin")` checks for — no corresponding Postgres `User` row is
required for this check to pass, though most Admin routes that read/write
domain data (e.g. `GET /api/riders`) will naturally start returning real
data as soon as riders/drivers exist.

## Why this is manual, not scripted

Automating this (a CDK custom resource, a one-off Lambda, a seed script that
takes real AWS credentials) would mean either committing a real admin
password/email to a script, or building credential-handling machinery for
something that happens once per environment. A few `aws` CLI commands run
by hand, once, by whoever has the account credentials anyway, is the
smaller and more auditable surface.
