import { prisma } from "../db/prisma";
import { maybeMatchPendingTrips } from "./matching";

/**
 * Persists a driver's reported position onto their Driver row (lastLat /
 * lastLng / lastLocationAt) so trip matching can prefer the nearest eligible
 * driver — the in-memory realtime hub (realtime/hub.ts) still serves the
 * admin Live Map and rider trip rooms unchanged; this is the durable copy
 * matching reads.
 *
 * Writes are throttled per driver: the driver app's REST ping is every 20 s
 * (driver_home_screen.dart), but the WebSocket feed while on a trip can be
 * every few seconds, and matching only needs "where are they within the last
 * couple of minutes". The throttle map is per process (see
 * docs/realtime-architecture.md — the API runs as a single App Runner
 * instance); a second instance would simply write a little more often, never
 * less, so it is safe even if that ever changes.
 */
export const LOCATION_PERSIST_MIN_INTERVAL_MS = 10_000;

const lastPersistedAt = new Map<string, number>();

export async function persistDriverLocation(
  driverId: string,
  lat: number,
  lng: number,
  { force = false }: { force?: boolean } = {},
): Promise<boolean> {
  const now = Date.now();
  const last = lastPersistedAt.get(driverId) ?? 0;
  if (!force && now - last < LOCATION_PERSIST_MIN_INTERVAL_MS) return false;
  lastPersistedAt.set(driverId, now);
  await prisma.driver.update({
    where: { id: driverId },
    data: { lastLat: lat, lastLng: lng, lastLocationAt: new Date(now) },
  });
  // A driver reporting a position is exactly when a nearby rider's waiting
  // request may become matchable (the request may have found no one close
  // enough a moment ago). Never blocks or fails the ping itself.
  void maybeMatchPendingTrips();
  return true;
}

/** Test hook: forget the per-driver write throttle. */
export function resetDriverLocationThrottle(): void {
  lastPersistedAt.clear();
}
