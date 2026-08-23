import type { Server as HttpServer } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { broadcastDriverLocation, joinDriverRoom, joinTripRoom, leaveAllRooms, recordDriverLocation } from "./hub";

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

// No id is ever accepted from the client here — the driver room joined is
// resolved from this connection's own verified identity (the same `user`
// every other handler on this socket already trusts), so a driver can only
// ever subscribe to their own assignment channel, never another driver's.
async function handleSubscribeDriver(socket: WebSocket, user: ConnectionUser) {
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: user.sub } } });
  if (!driver) {
    return send(socket, { type: "error", message: "Only drivers can subscribe to assignment events" });
  }
  joinDriverRoom(driver.id, socket);
  send(socket, { type: "subscribed_driver", driverId: driver.id });
}

function processMessage(socket: WebSocket, user: ConnectionUser, raw: unknown) {
  let parsed: unknown;
  try {
    parsed = JSON.parse(String(raw));
  } catch {
    return send(socket, { type: "error", message: "Invalid JSON" });
  }
  if (typeof parsed !== "object" || parsed === null || !("type" in parsed)) {
    return send(socket, { type: "error", message: "Message must have a type" });
  }

  const message = parsed as Record<string, unknown>;
  if (message.type === "subscribe") {
    void handleSubscribe(socket, user, message.tripId);
  } else if (message.type === "subscribe_driver") {
    void handleSubscribeDriver(socket, user);
  } else if (message.type === "location") {
    void handleLocation(socket, user, message.lat, message.lng);
  } else {
    send(socket, { type: "error", message: `Unknown message type: ${String(message.type)}` });
  }
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

    // Registered synchronously, before any of the awaits below (token
    // verification, then the suspension check) — `ws` starts parsing bytes
    // off the underlying socket as soon as the connection is accepted, and
    // an EventEmitter drops any event with no listener attached at the
    // moment it fires. A client that sends its first message immediately
    // after the connection opens (a legitimate pattern this file's own
    // tests exercise) can otherwise race ahead of those awaits and have
    // that message silently lost. Queue anything that arrives before
    // `user` is resolved and drain the queue once auth completes, instead
    // of narrowing the race without closing it.
    const pendingMessages: unknown[] = [];
    let onMessage: (raw: unknown) => void = (raw) => {
      pendingMessages.push(raw);
    };
    socket.on("message", (raw) => onMessage(raw));
    socket.on("close", () => {
      leaveAllRooms(socket);
      connectionUsers.delete(socket);
    });

    let user: ConnectionUser;
    try {
      const payload = await verifier.verify(token);
      user = {
        sub: payload.sub,
        groups: Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [],
      };
    } catch {
      socket.close(4401, "Invalid or expired token");
      return;
    }

    // Same suspension check requireAuth enforces on every HTTP route (see
    // middleware/auth.ts) — without it, a suspended user's still-valid JWT
    // would keep working over this separate WS entry point after HTTP access
    // was cut off. Admins are exempt for the same recovery-action reason;
    // a caller with no User row yet isn't blocked.
    if (!user.groups.includes("Admin")) {
      const dbUser = await prisma.user.findUnique({ where: { cognitoSub: user.sub }, select: { suspended: true } });
      if (dbUser?.suspended) {
        socket.close(4403, "Account suspended");
        return;
      }
    }

    connectionUsers.set(socket, user);
    onMessage = (raw) => processMessage(socket, user, raw);
    for (const raw of pendingMessages) processMessage(socket, user, raw);
  });

  return wss;
}
