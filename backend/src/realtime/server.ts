import type { Server as HttpServer } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import {
  broadcastDriverLocation,
  joinFleetRoom,
  joinTripRoom,
  leaveAllRooms,
  recordDriverLocation,
  registerDriverSocket,
  unregisterDriverSocket,
} from "./hub";

interface ConnectionUser {
  sub: string;
  groups: string[];
}

const connectionUsers = new WeakMap<WebSocket, ConnectionUser>();
const messageTimestamps = new WeakMap<WebSocket, number[]>();
const WS_RATE_LIMIT = 30;
const WS_RATE_WINDOW_MS = 10_000;

function isRateLimited(socket: WebSocket): boolean {
  const now = Date.now();
  let timestamps = messageTimestamps.get(socket);
  if (!timestamps) {
    timestamps = [];
    messageTimestamps.set(socket, timestamps);
  }
  while (timestamps.length > 0 && timestamps[0] < now - WS_RATE_WINDOW_MS) {
    timestamps.shift();
  }
  if (timestamps.length >= WS_RATE_LIMIT) return true;
  timestamps.push(now);
  return false;
}

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

// Admin-only: join the platform-wide fleet presence room. A driver or rider
// socket asking for this gets a plain error, same shape as the trip-room
// authorization failure above — never a silent partial grant.
function handleFleetSubscribe(socket: WebSocket, user: ConnectionUser) {
  if (!user.groups.includes("Admin")) {
    return send(socket, { type: "error", message: "Only Admin can subscribe to fleet presence" });
  }
  joinFleetRoom(socket);
  send(socket, { type: "subscribed:fleet" });
}

async function handleLocation(socket: WebSocket, user: ConnectionUser, lat: unknown, lng: unknown) {
  if (typeof lat !== "number" || typeof lng !== "number") {
    return send(socket, { type: "error", message: "location requires numeric lat/lng" });
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

export function attachRealtime(server: HttpServer) {
  const wss = new WebSocketServer({ server, path: "/ws" });

  wss.on("connection", (socket, request) => {
    const url = new URL(request.url ?? "", "http://localhost");
    const token = url.searchParams.get("token");
    if (!token) {
      socket.close(4401, "Missing token");
      return;
    }

    // Verifying the token and looking up the caller's Driver row are both
    // async (a JWT verify round-trip and a DB query), but `message`/`close`
    // must be attached synchronously, before either starts — `ws` doesn't
    // buffer events for listeners registered after they fire, so a message
    // the client sends right after the socket opens (immediately following
    // `waitForOpen`, well before this resolves) would otherwise be silently
    // and permanently dropped instead of merely delayed. Every handler
    // below awaits this same promise instead of reading connectionUsers
    // directly, so a message that arrives mid-auth now correctly waits for
    // it rather than racing it.
    const authPromise = (async (): Promise<ConnectionUser | null> => {
      try {
        const payload = await verifier.verify(token);
        const user: ConnectionUser = {
          sub: payload.sub,
          groups: Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [],
        };
        connectionUsers.set(socket, user);

        const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: user.sub } } });
        if (driver) {
          registerDriverSocket(driver.id, socket);
        }
        return user;
      } catch {
        socket.close(4401, "Invalid or expired token");
        return null;
      }
    })();

    socket.on("message", (raw) => {
      void (async () => {
        const user = await authPromise;
        if (!user) return;
        if (isRateLimited(socket)) {
          return send(socket, { type: "error", message: "Rate limit exceeded" });
        }

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
        } else if (message.type === "subscribe:fleet") {
          handleFleetSubscribe(socket, user);
        } else if (message.type === "location") {
          void handleLocation(socket, user, message.lat, message.lng);
        } else {
          send(socket, { type: "error", message: `Unknown message type: ${String(message.type)}` });
        }
      })();
    });

    socket.on("close", async () => {
      leaveAllRooms(socket);
      const closingUser = await authPromise.catch(() => null);
      if (closingUser) {
        const closingDriver = await prisma.driver.findFirst({ where: { user: { cognitoSub: closingUser.sub } } });
        if (closingDriver) unregisterDriverSocket(closingDriver.id, socket);
      }
      connectionUsers.delete(socket);
    });
  });

  return wss;
}
