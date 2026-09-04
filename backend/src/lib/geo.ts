/**
 * Server-side distance. The client is NOT trusted to assert the chargeable
 * distance (that let a rider post distanceKm:0 and collapse the fare to base —
 * P0 #10). Instead the client sends pickup + dropoff COORDINATES, which the
 * server validates and turns into a great-circle distance here.
 *
 * Great-circle (haversine) is the honest MVP metric — the same one the rider
 * app used to compute client-side — and it is a lower bound on real routed
 * distance, so it can never over-charge. When a routing provider (Google
 * Distance Matrix, etc.) is wired server-side later, it slots in behind this
 * same function signature without changing any caller.
 */

export interface Coordinate {
  lat: number;
  lng: number;
}

const EARTH_RADIUS_KM = 6371;
const toRad = (deg: number): number => (deg * Math.PI) / 180;

/** Valid WGS84 coordinate: finite, lat in [-90,90], lng in [-180,180]. */
export function isValidCoordinate(c: Coordinate): boolean {
  return (
    Number.isFinite(c.lat) &&
    Number.isFinite(c.lng) &&
    c.lat >= -90 &&
    c.lat <= 90 &&
    c.lng >= -180 &&
    c.lng <= 180
  );
}

/** Great-circle distance in kilometres between two coordinates. */
export function haversineKm(a: Coordinate, b: Coordinate): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.sin(dLng / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return EARTH_RADIUS_KM * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Rough trip duration for a distance, at an assumed ~25 km/h average city
 * speed — matching the estimate the rider app used to show. Derived from the
 * server-computed distance, never taken from the client.
 */
export function estimateDurationMinutes(distanceKm: number): number {
  return (distanceKm / 25) * 60;
}

// A single ride can't plausibly exceed this; a value past it means the
// coordinates are wrong (or hostile), so we reject rather than price it.
export const MAX_TRIP_DISTANCE_KM = 2000;
