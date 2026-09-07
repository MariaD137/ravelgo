import type { WebSocket } from "ws";

export interface DriverLocation {
  driverId: string;
  lat: number;
  lng: number;
  updatedAt: string;
}

export interface RiderLocation {
  tripId: string;
  lat: number;
  lng: number;
  updatedAt: string;
}

// In-memory on purpose — see docs/realtime-architecture.md's "trade-off, on
// the record" section for exactly when this needs to become a shared store
// instead (the day App Runner runs more than one instance, not before).
const tripRooms = new Map<string, Set<WebSocket>>();
const latestDriverLocation = new Map<string, DriverLocation>();
// Keyed by tripId, not riderId — a rider's position is only ever meaningful
// (and only ever reported, see POST /trips/:id/rider-location) in the
// context of one specific active trip. Entries are removed explicitly by
// clearRiderLocation once that trip reaches a terminal status (see
// trips.routes.ts), rather than left to expire on their own — unlike
// drivers (a roughly-fixed population), trips are created continuously, so
// an unbounded map here would be a real memory leak.
const latestRiderLocation = new Map<string, RiderLocation>();

// A location report older than this is no longer "live" for monitoring
// purposes. Set comfortably above every reporting cadence in the apps (the
// driver app's idle REST ping is every 20s, its mid-trip WebSocket push is
// every 5s; the rider app's trip ping is every 15s) so ordinary network
// jitter never flickers a fresh entity between LIVE and STALE. Shared by the
// admin live map and any other consumer of these locations (e.g. a
// customer's own delivery tracking screen) so "live" means one thing
// everywhere it's shown.
export const LIVE_LOCATION_THRESHOLD_MS = 30_000;

export function locationFreshness(updatedAt: string): "LIVE" | "STALE" {
  return Date.now() - new Date(updatedAt).getTime() <= LIVE_LOCATION_THRESHOLD_MS ? "LIVE" : "STALE";
}

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

/** Every driver location known to this instance — the admin live map's data source. */
export function getAllDriverLocations(): DriverLocation[] {
  return [...latestDriverLocation.values()];
}

export function broadcastDriverLocation(tripId: string, location: DriverLocation) {
  broadcastToTrip(tripId, { type: "location", tripId, ...location });
}

export function recordRiderLocation(tripId: string, lat: number, lng: number): RiderLocation {
  const location: RiderLocation = { tripId, lat, lng, updatedAt: new Date().toISOString() };
  latestRiderLocation.set(tripId, location);
  return location;
}

export function getRiderLocation(tripId: string): RiderLocation | undefined {
  return latestRiderLocation.get(tripId);
}

/** Stop tracking a trip's rider position — called once it reaches a terminal status. */
export function clearRiderLocation(tripId: string): void {
  latestRiderLocation.delete(tripId);
}

// Test-only: without this, `resetDb()` between test files would leave stale
// state (rooms, cached locations) in this in-memory hub across whichever
// tests happen to run in the same process — reuse the exact "reset shared
// state between tests" pattern already used for the DB in test/helpers.ts.
export function resetRealtimeState() {
  tripRooms.clear();
  latestDriverLocation.clear();
  latestRiderLocation.clear();
}
