import { createServer } from "node:http";
import { app } from "./app";
import { env } from "./config/env";
import { attachRealtime } from "./realtime/server";

const server = createServer(app);
attachRealtime(server);

server.listen(env.PORT, () => {
  console.log(`RavelGo backend listening on port ${env.PORT} (${env.NODE_ENV})`);
});
