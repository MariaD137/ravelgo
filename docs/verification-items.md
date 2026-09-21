# RavelGo — verification items

Four items from the three-app gap audit could not be resolved by reading
application code alone, because what they depend on lives in AWS
configuration or in a third-party dashboard. This records exactly what the
repository does say about each, and exactly what is left to confirm against
the live account.

**Nothing here is a live verification.** No AWS or Paystack call was made
while writing this. Each item states what can be read from the code and what
still has to be checked by someone with account access.

## X-3 — Device push notifications

**What the code says.** The path is complete end to end and uses AWS
Pinpoint, with no Firebase SDK anywhere:

- `infra/lib/auth-stack.ts` creates the Pinpoint Application, plus a
  dedicated unauthenticated Cognito identity pool whose role is scoped to
  `mobiletargeting:UpdateEndpoint` and `mobiletargeting:PutEvents` against
  that one application. It can never send a message.
- `infra/lib/api-stack.ts` grants the backend `SendMessages` against the same
  application and passes `PINPOINT_APPLICATION_ID` to the service.
- `backend/src/services/push.ts` sends to the raw device token and prunes
  tokens Pinpoint reports as permanently undeliverable.
- Both apps register and de-register tokens through
  `POST`/`DELETE /api/notifications/device-tokens`.

**What is not verified.** The Pinpoint Application exists as soon as the
stack deploys, but its GCM (Android) and APNs (iOS) channels carry no
credential until someone supplies a real FCM server key and APNs signing
key. `infra/lib/api-stack.ts` documents the two CLI calls that do it. Until
then every send fails per address, which the backend already tolerates: the
in-app notification row is written either way.

**To confirm on the account:** `aws pinpoint get-gcm-channel` and
`get-apns-channel` for the application id, checking `Enabled: true` and a
credential present. Then send one real notification to a physical device.

## B-12 — Paystack

**What the code says.** Paystack is the only payment provider; there is no
Stripe code left, only comments recording its removal.

- The secret key is read from the environment
  (`backend/src/config/env.ts`), is required in production, and is stored in
  Secrets Manager by `infra/lib/api-stack.ts`, which seeds the deliberate
  placeholder `sk_live_REPLACE_ME`.
- `backend/src/billing/paystack.ts#evaluatePaystackKey` refuses that
  placeholder, an unset value, and anything that is not a well-formed
  `sk_test_`/`sk_live_` key, so a misconfigured server says so plainly
  instead of surfacing a Paystack 401 as a generic 500.
- Webhook signatures are verified with a constant-time comparison against
  the raw request body, on a route mounted before the JSON body parser so
  the bytes are unmodified.

**What is not verified.** Whether the live secret in Secrets Manager has
actually been replaced, whether the account is in test or live mode, and
whether the webhook URL is registered in the Paystack dashboard. None of
that is observable from this repository.

**To confirm on the account:** read the secret's mode prefix (never the
value) via the health surface, then run one real test-mode charge end to end
and confirm the webhook arrives and the trip settles.

## I-2 — S3 lifecycle

**What the code says** (`infra/lib/storage-stack.ts`):

| Bucket | Public access | Encryption | TLS | Versioning | Lifecycle |
| --- | --- | --- | --- | --- | --- |
| Documents | Blocked | S3-managed | Enforced | On | Noncurrent versions expire after 90 days |
| Assets | Blocked | S3-managed | Enforced | Off | None |

Driver documents are private and reachable only through short-lived
presigned URLs; upload CORS is scoped to the CloudFront domain the web apps
are served from rather than `*`.

**The gap.** The assets bucket has no lifecycle rule at all, and the
documents bucket expires only *noncurrent* versions — a current object lives
forever. Nothing deletes the documents of a driver who was rejected or who
left, so identity documents accumulate indefinitely. That is a data
retention decision, not a bug: someone has to say how long RavelGo may keep
a rejected applicant's licence and ID. It is listed as a remaining product
decision rather than changed here.

**To confirm on the account:** `aws s3api get-bucket-lifecycle-configuration`
on both buckets, to see whether a rule was added outside CDK.

## I-3 — Google Maps API key

**What the code says.** The key never lives in the repository. It reaches a
build from a GitHub Actions secret named `GOOGLE_MAPS_API_KEY`:

- `android-build.yml` writes it into the app's `.env` at build time.
- `staging-deploy.yml` and `production-web-deploy.yml` inject a
  `maps.googleapis.com` script tag into `web/index.html` at build time, and
  both guard on the secret being non-empty.
- `infra/lib/api-stack.ts` keeps a server-side key in Secrets Manager for
  the backend's own geocoding and Places routes, granted read-only to the
  service role.

A browser key is necessarily public once a web build ships — it is visible
in the page source by design.

**What is not verified.** Whether the browser key is restricted by HTTP
referrer to the CloudFront domain (and any custom domain), whether the
Android key is restricted by package name and signing certificate
fingerprint, whether the server key is restricted by API rather than
referrer, and whether billing quotas and alerts are set. An unrestricted
browser key can be lifted from the page and spent by anyone.

**To confirm on the account:** Google Cloud Console → Credentials, checking
application restrictions and API restrictions on each of the three keys.
