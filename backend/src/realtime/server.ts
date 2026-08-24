import type { Server as HttpServer } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { broadcastDriverLocation, joinFleetRoom, joinTripRoom, leaveAllRooms, recordDriverLocation } from "./hub";

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

  wss.on("connection", async (socket, request) => {
    const url = new URL(request.url ?? "", "http://localhost");
    const token = url.searchParams.get("token");
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
      } else if (message.type === "subscribe:fleet") {
        handleFleetSubscribe(socket, user);
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
