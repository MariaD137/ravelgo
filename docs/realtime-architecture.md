# RT-01: Real-time architecture decision

## The choice: a `ws` WebSocket server on the same App Runner container

Not AWS AppSync (GraphQL subscriptions). Both were on the table; this is
why one won.

## Why not AppSync

AppSync is the more "managed" answer — subscriptions, connection fan-out,
and horizontal scaling come for free, and it fits AWS-native stacks well.
But two things ruled it out for where this project actually is right now:

- **It can't be built or tested without a real AWS account.** Every other
  piece of this backend (routes, matching, the WebSocket layer below) has
  been built and verified against a real local Postgres and real HTTP/WS
  clients in this sandbox — zero AWS credentials needed until deploy time.
  AppSync has no equivalent local-first workflow: the schema, resolvers, and
  subscription wiring only really get exercised against a deployed API.
- **It's a second real-time system next to a nonexistent first one.**
  There's no existing GraphQL layer in this API — introducing AppSync here
  means learning and maintaining a second query language and a second
  deployment surface (a `RavelGo-Realtime` CDK stack, VTL or JS resolvers,
  a separate IAM/auth story) for a single feature. That's a bigger
  architectural commitment than the current problem — three real-time
  events (driver location, trip status, and the future ride-matching push)
  — actually needs yet.

## Why `ws` on the same container

- **One container, one deploy, same auth.** `RavelGo-Api`'s App Runner
  service already runs the Express app as a single process (see
  `infra/README.md` — no NAT, one container, deliberately not
  over-provisioned). Attaching a `ws` server to the same `http.Server`
  Express already listens on (see `src/index.ts`) means no new
  infrastructure, no new service to deploy or monitor, and — critically —
  it reuses the exact same Cognito JWT verification already built in
  `src/middleware/auth.ts`, just applied to a connection instead of a
  request.
- **Directly testable.** `src/realtime/hub.ts` and the WebSocket connection
  handling in `src/realtime/server.ts` are exercised in
  `src/routes/realtime.test.ts` against a real `ws` client and a real HTTP
  server — the same rigor as every other route in this backend (see
  `backend/README.md`'s Tests section). AppSync subscriptions have no
  comparable "spin it up and connect a real client" story outside AWS.

## The trade-off, on the record

This does **not** scale past one App Runner instance. `src/realtime/hub.ts`
keeps subscriptions and the latest driver location in an in-memory `Map` —
if App Runner ever runs more than one instance, a rider connected to
instance A will never see a broadcast triggered by a status update that hit
instance B. That's the concrete, specific trigger to revisit this decision:
the day App Runner's `RavelGo-Api` service needs more than one running
instance (real concurrent load, not before), replace the in-memory hub with
a shared pub/sub backend (Redis, or at that point AppSync starts looking
more attractive since the single-container assumption above no longer
holds) so broadcasts fan out across instances.

## What's built on top of this

- **RT-02 — driver location streaming**: `{"type":"location"}` messages
  from a driver's WebSocket connection, broadcast to every other connection
  subscribed to that driver's active trip. `GET /api/trips/:id/driver-location`
  is an HTTP polling fallback for clients that aren't WS-connected yet — see
  `src/routes/trips.routes.ts`.
- **RT-03 — live trip status push**: `PATCH /api/trips/:id/status` broadcasts
  a `{"type":"trip:status"}` event to everyone subscribed to that trip's
  room, immediately after the Postgres write succeeds.
- **RT-04 — ride-matching**: not part of the WebSocket layer itself —
  `src/services/matching.ts` runs synchronously inside `POST /api/trips`,
  see that file's own notes on why a synchronous "first available driver"
  match is the right starting point rather than a queue/worker.
- **RT-05 — admin fleet presence**: a platform-wide room (not scoped to one
  trip), Admin-only. An Admin-authenticated connection sends
  `{"type":"subscribe:fleet"}` and receives `driver:online`,
  `driver:offline`, `driver:suspended`, `driver:trip_started`, and
  `driver:trip_completed` events for every driver, not just ones on a trip
  the admin is already watching — see `PATCH /api/drivers/me/online`,
  `PATCH /api/drivers/:id/status`, and `PATCH /api/trips/:id/status` in
  `src/routes/`, and `joinFleetRoom`/`broadcastFleetEvent` in
  `src/realtime/hub.ts`. `GET /api/admin/drivers/presence` is the
  HTTP-polling equivalent (a point-in-time snapshot) for an admin client
  that isn't WS-connected. Same in-memory, single-instance caveat as the
  rest of this hub — see "The trade-off, on the record" above.

## Wire protocol (client-facing)

Connect: `wss://<host>/ws?token=<Cognito access token>`. The token is
verified with the same `CognitoJwtVerifier` as HTTP requests; an invalid or
missing token closes the socket immediately (code `4401`).

Client → server messages (JSON):
```
{"type":"subscribe","tripId":"..."}      // join a trip's room, if authorized
{"type":"subscribe:fleet"}               // Admin only — join the platform-wide fleet presence room
{"type":"location","lat":0,"lng":0}      // driver only — pushes their location
```

Server → client messages (JSON):
```
{"type":"subscribed","tripId":"..."}
{"type":"subscribed:fleet"}
{"type":"error","message":"..."}
{"type":"trip:status","tripId":"...","status":"...","finalFare":null}
{"type":"location","tripId":"...","driverId":"...","lat":0,"lng":0,"updatedAt":"..."}
{"type":"driver:online","driverId":"...","at":"..."}
{"type":"driver:offline","driverId":"...","at":"..."}
{"type":"driver:suspended","driverId":"..."}
{"type":"driver:trip_started","driverId":"...","tripId":"..."}
{"type":"driver:trip_completed","driverId":"...","tripId":"..."}
```
