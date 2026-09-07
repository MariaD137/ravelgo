import type { IncomingMessage, Server as HttpServer } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { isValidCoordinate } from "../lib/geo";
import { broadcastDriverLocation, joinTripRoom, leaveAllRooms, recordDriverLocation } from "./hub";

interface ConnectionUser {
  sub: string;
  groups: string[];
}

const connectionUsers = new WeakMap<WebSocket, ConnectionUser>();

function send(socket: WebSocket, payload: unknown) {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(payload));
}

async function isAuthorizedForTrip(user: ConnectionUser, tripId: string): Promise<boolean> {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    include: { rider: true, driver: { include: { user: true } } },
  });
  if (!trip) return false;
  if (user.groups.includes("Admin")) return true;
  return trip.rider.cognitoSub === user.sub || trip.driver?.user.cognitoSub === user.sub;
}

async function handleSubscribe(socket: WebSocket, user: ConnectionUser, tripId: unknown) {
  if (typeof tripId !== "string" || !tripId) {
    return send(socket, { type: "error", message: "subscribe requires a tripId" });
  }
  const authorized = await isAuthorizedForTrip(user, tripId);
  if (!authorized) {
    return send(socket, { type: "error", message: "Not authorized to subscribe to this trip" });
  }
  joinTripRoom(tripId, socket);
  send(socket, { type: "subscribed", tripId });
}

async function handleLocation(socket: WebSocket, user: ConnectionUser, lat: unknown, lng: unknown) {
  if (typeof lat !== "number" || typeof lng !== "number") {
    return send(socket, { type: "error", message: "location requires numeric lat/lng" });
  }
  if (!isValidCoordinate({ lat, lng })) {
    return send(socket, { type: "error", message: "lat/lng out of range" });
  }
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: user.sub } } });
  if (!driver) {
    return send(socket, { type: "error", message: "Only drivers can push a location" });
  }

  const location = recordDriverLocation(driver.id, lat, lng);
  const activeTrips = await prisma.trip.findMany({
    where: { driverId: driver.id, status: { in: ["MATCHED", "IN_PROGRESS"] } },
    select: { id: true },
  });
  for (const trip of activeTrips) {
    broadcastDriverLocation(trip.id, location);
  }
}

/**
 * Pull the access token out of the connection request. Preferred: the
 * `Sec-WebSocket-Protocol` header, sent by the client as `["bearer", <token>]`
 * — this keeps the token out of the URL (query strings are the most commonly
 * logged by proxies/load balancers). Falls back to a `?token=` query param for
 * older clients and tests.
 */
function extractToken(request: IncomingMessage): string | null {
  const header = request.headers["sec-websocket-protocol"];
  if (typeof header === "string") {
    const parts = header.split(",").map((s) => s.trim());
    const idx = parts.indexOf("bearer");
    if (idx !== -1 && parts[idx + 1]) return parts[idx + 1];
  }
  const url = new URL(request.url ?? "", "http://localhost");
  return url.searchParams.get("token");
}

export function attachRealtime(server: HttpServer) {
  const wss = new WebSocketServer({
    server,
    path: "/ws",
    // Accept (echo) the "bearer" subprotocol so browsers that offer it don't
    // fail the handshake. The token rides alongside it and is read below.
    handleProtocols: (protocols) => (protocols.has("bearer") ? "bearer" : false),
  });

  wss.on("connection", async (socket, request) => {
    const token = extractToken(request);
    if (!token) {
      socket.close(4401, "Missing token");
      return;
    }

    try {
      const payload = await verifier.verify(token);
      const user: ConnectionUser = {
        sub: payload.sub,
        groups: Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [],
      };
      connectionUsers.set(socket, user);
    } catch {
      socket.close(4401, "Invalid or expired token");
      return;
    }

    socket.on("message", (raw) => {
      const user = connectionUsers.get(socket);
      if (!user) return;

      let parsed: unknown;
      try {
        parsed = JSON.parse(raw.toString());
      } catch {
        return send(socket, { type: "error", message: "Invalid JSON" });
      }
      if (typeof parsed !== "object" || parsed === null || !("type" in parsed)) {
        return send(socket, { type: "error", message: "Message must have a type" });
      }

      const message = parsed as Record<string, unknown>;
      if (message.type === "subscribe") {
        void handleSubscribe(socket, user, message.tripId);
      } else if (message.type === "location") {
        void handleLocation(socket, user, message.lat, message.lng);
      } else {
        send(socket, { type: "error", message: `Unknown message type: ${String(message.type)}` });
      }
    });

    socket.on("close", () => {
      leaveAllRooms(socket);
      connectionUsers.delete(socket);
    });
  });

  return wss;
}
