import type { WebSocket } from "ws";

export interface DriverLocation {
  driverId: string;
  lat: number;
  lng: number;
  updatedAt: string;
}

// In-memory on purpose — see docs/realtime-architecture.md's "trade-off, on
// the record" section for exactly when this needs to become a shared store
// instead (the day App Runner runs more than one instance, not before).
const tripRooms = new Map<string, Set<WebSocket>>();
const latestDriverLocation = new Map<string, DriverLocation>();
// One room per driver, joined only by that driver's own authenticated
// connection (server.ts's handleSubscribeDriver resolves the driverId from
// the connection's own verified identity — a client never supplies one),
// so a driver can never subscribe to, and therefore never receive, another
// driver's assignment events.
const driverRooms = new Map<string, Set<WebSocket>>();

export function joinTripRoom(tripId: string, socket: WebSocket) {
  let room = tripRooms.get(tripId);
  if (!room) {
    room = new Set();
    tripRooms.set(tripId, room);
  }
  room.add(socket);
}

export function joinDriverRoom(driverId: string, socket: WebSocket) {
  let room = driverRooms.get(driverId);
  if (!room) {
    room = new Set();
    driverRooms.set(driverId, room);
  }
  room.add(socket);
}

export function leaveAllRooms(socket: WebSocket) {
  for (const room of tripRooms.values()) {
    room.delete(socket);
  }
  for (const room of driverRooms.values()) {
    room.delete(socket);
  }
}

function broadcastToTrip(tripId: string, payload: unknown) {
  const room = tripRooms.get(tripId);
  if (!room || room.size === 0) return;
  const message = JSON.stringify(payload);
  for (const socket of room) {
    if (socket.readyState === socket.OPEN) socket.send(message);
  }
}

export function broadcastTripStatus(tripId: string, status: string, finalFare: number | null) {
  broadcastToTrip(tripId, { type: "trip:status", tripId, status, finalFare });
}

export function recordDriverLocation(driverId: string, lat: number, lng: number): DriverLocation {
  const location: DriverLocation = { driverId, lat, lng, updatedAt: new Date().toISOString() };
  latestDriverLocation.set(driverId, location);
  return location;
}

export function getLatestDriverLocation(driverId: string): DriverLocation | undefined {
  return latestDriverLocation.get(driverId);
}

export function broadcastDriverLocation(tripId: string, location: DriverLocation) {
  broadcastToTrip(tripId, { type: "location", tripId, ...location });
}

/** Notifies a driver's own connection(s) that they've been given a new
 * assignment — a lightweight "something changed, go re-fetch" signal (the
 * same shape as broadcastTripStatus), not a full data payload. The driver
 * app is expected to follow up with GET /api/drivers/me/assignment (or, for
 * a RIDE, GET /api/trips/:id) for the details, exactly as RideSession does
 * on the rider side for trip:status. */
export function broadcastDriverAssignment(
  driverId: string,
  assignmentType: "RIDE" | "COURIER" | "RENTAL",
  assignmentId: string,
) {
  const room = driverRooms.get(driverId);
  if (!room || room.size === 0) return;
  const message = JSON.stringify({ type: "driver:assignment", assignmentType, assignmentId });
  for (const socket of room) {
    if (socket.readyState === socket.OPEN) socket.send(message);
  }
}

/** Notifies a driver's own connection(s) that they've been sent a real ride
 * offer (see services/matching.ts's offerNextDriver) — the same
 * lightweight "something changed, go re-fetch" shape as
 * broadcastDriverAssignment, deliberately distinct from it: an offer is not
 * yet a committed assignment, and the driver app must not treat this as
 * "you have a new job" the way it does driver:assignment — only as "go
 * check GET /api/drivers/me/offer". */
export function broadcastDriverOffer(driverId: string, tripId: string) {
  const room = driverRooms.get(driverId);
  if (!room || room.size === 0) return;
  const message = JSON.stringify({ type: "driver:offer", tripId });
  for (const socket of room) {
    if (socket.readyState === socket.OPEN) socket.send(message);
  }
}

// Test-only: without this, `resetDb()` between test files would leave stale
// state (rooms, cached locations) in this in-memory hub across whichever
// tests happen to run in the same process — reuse the exact "reset shared
// state between tests" pattern already used for the DB in test/helpers.ts.
export function resetRealtimeState() {
  tripRooms.clear();
  driverRooms.clear();
  latestDriverLocation.clear();
}
