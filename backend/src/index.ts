import { createServer } from "node:http";
import { app } from "./app";
import { env } from "./config/env";
import { attachRealtime } from "./realtime/server";
import { startOfferExpirySweep } from "./services/matching";
import { startRentalBookingSweep } from "./services/rental-payment";

// Last-resort safety nets. express-async-errors routes handler rejections to
// errorHandler, so these should rarely fire — but a stray rejection from a
// background task (a fire-and-forget audit write, a realtime broadcast) must
// not silently terminate the API. Log with enough detail to debug; keep the
// process alive on an unhandled rejection (Node would otherwise exit on
// newer versions). An uncaughtException leaves the process in an unknown
// state, so there we log and exit so the orchestrator (App Runner) restarts
// a clean instance.
process.on("unhandledRejection", (reason) => {
  console.error("[unhandledRejection]", reason);
});
process.on("uncaughtException", (err) => {
  console.error("[uncaughtException]", err);
  process.exit(1);
});

const server = createServer(app);
attachRealtime(server);

server.listen(env.PORT, () => {
  console.log(`RavelGo backend listening on port ${env.PORT} (${env.NODE_ENV})`);
});

// Releases any ride offer nobody responded to in time and re-offers it to
// the next eligible driver (services/matching.ts) — the fallback for a
// driver who never explicitly declines at all.
startOfferExpirySweep();

// Backstop for closing out CONFIRMED rental bookings whose dates have
// passed — the opportunistic reconciliation in rentals.routes.ts already
// covers every actual read path; this just catches a booking nobody reads
// for a while.
startRentalBookingSweep();
