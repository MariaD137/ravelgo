import { createServer } from "node:http";
import { app } from "./app";
import { env } from "./config/env";
import { prisma } from "./db/prisma";
import { attachRealtime } from "./realtime/server";

const server = createServer(app);
const wss = attachRealtime(server);

server.listen(env.PORT, () => {
  console.log(`RavelGo backend listening on port ${env.PORT} (${env.NODE_ENV})`);
});

// App Runner (and any container orchestrator) sends SIGTERM to ask for a
// clean stop before killing the process outright — without a handler, Node
// exits immediately on the default signal disposition, dropping in-flight
// HTTP/WebSocket requests and leaving the Postgres connection pool closed
// uncleanly instead of returning connections to the server first. Stop
// accepting new connections, let in-flight ones finish, then close the
// Prisma connection pool before exiting. SIGINT covers the same local
// Ctrl-C case in development.
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`${signal} received, shutting down gracefully`);

  // http.Server.close() only stops accepting new connections — it does not
  // touch already-upgraded WebSocket sockets, which would otherwise sit
  // open until the force-exit timer below kills the process out from under
  // them. Send each one a real close frame first so clients get a clean
  // "server going away" signal instead of an abrupt reset.
  for (const client of wss.clients) {
    client.close(1001, "Server shutting down");
  }
  wss.close();

  server.close(async () => {
    await prisma.$disconnect();
    process.exit(0);
  });

  // If in-flight requests (or an open WebSocket) never drain, don't hang
  // forever — force-exit after a bounded grace period.
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
