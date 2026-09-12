import { createServer } from "node:http";
import { app } from "./app";
import { PAYSTACK_UNCONFIGURED_MESSAGE, paystackConfig } from "./billing/paystack";
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
  // Deliberately a loud log rather than a boot failure: a bad Paystack key
  // breaks card payments, wallet top-ups and payouts (each of which now
  // fails with a clear PAYMENT_PROVIDER_ERROR), but rides, deliveries,
  // cash trips and everything else keep working — taking the whole API down
  // for one integration's config would be worse. env.ts still refuses to
  // boot in production when the key is missing entirely; /health reports
  // this status so a deploy can be verified without reading logs.
  if (paystackConfig.configured) {
    console.log(`[config] Paystack: configured (${paystackConfig.mode} mode)`);
  } else {
    console.error(`[config] Paystack: UNCONFIGURED — ${PAYSTACK_UNCONFIGURED_MESSAGE}`);
  }
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
