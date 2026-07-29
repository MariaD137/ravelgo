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

export function joinTripRoom(tripId: string, socket: WebSocket) {
  let room = tripRooms.get(tripId);
  if (!room) {
    room = new Set();
    tripRooms.set(tripId, room);
  }
  room.add(socket);
}

export function leaveAllRooms(socket: WebSocket) {
  for (const room of tripRooms.values()) {
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

// Test-only: without this, `resetDb()` between test files would leave stale
// state (rooms, cached locations) in this in-memory hub across whichever
// tests happen to run in the same process — reuse the exact "reset shared
// state between tests" pattern already used for the DB in test/helpers.ts.
export function resetRealtimeState() {
  tripRooms.clear();
  latestDriverLocation.clear();
}
