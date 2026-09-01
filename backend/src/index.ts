import { createServer } from "node:http";
import { app } from "./app";
import { env } from "./config/env";
import { attachRealtime } from "./realtime/server";

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
