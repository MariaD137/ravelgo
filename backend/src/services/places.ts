import { env } from "../config/env";
import { ApiError, Errors } from "../lib/errors";

/**
 * Server-side proxy for Google Maps Platform Places + Geocoding.
 *
 * Why this lives on the backend rather than being called straight from the
 * Flutter apps:
 *  - CORS: Google's Places/Geocoding *web service* endpoints do not send
 *    CORS headers, so a browser (Flutter Web) fetch to them is blocked. The
 *    map tiles use the Maps *JavaScript* SDK (a separate, browser key embedded
 *    in index.html); address search/geocoding must go through a same-origin
 *    backend instead.
 *  - Key hygiene: the key used here (GOOGLE_MAPS_SERVER_KEY) is never shipped
 *    to a client, so it can be restricted to the backend's egress IP and to
 *    just these APIs — unlike the browser key, which is necessarily public.
 *
 * The fetch implementation is injectable so tests exercise the parsing and
 * error mapping without a network call or a real key.
 */
export type FetchLike = (url: string) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>;

let fetchImpl: FetchLike = (url) => fetch(url);

/** Test seam: override the HTTP client. Returns the previous one so tests can restore it. */
export function __setFetch(f: FetchLike): FetchLike {
  const prev = fetchImpl;
  fetchImpl = f;
  return prev;
}

export interface PlaceSuggestion {
  placeId: string;
  description: string;
}

export interface PlaceLocation {
  address: string;
  lat: number;
  lng: number;
}

const BASE = "https://maps.googleapis.com/maps/api";

function requireKey(): string {
  const key = env.GOOGLE_MAPS_SERVER_KEY;
  if (!key) {
    // 503 (not 500): the code is fine, the deployment simply hasn't been given
    // a key yet. The message is safe to surface to the client.
    throw new ApiError(503, "SERVICE_UNAVAILABLE", "Location search is not configured on the server");
  }
  return key;
}

async function callGoogle(path: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const key = requireKey();
  const query = new URLSearchParams({ ...params, key }).toString();
  let res: Awaited<ReturnType<FetchLike>>;
  try {
    res = await fetchImpl(`${BASE}/${path}?${query}`);
  } catch {
    throw new ApiError(502, "UPSTREAM_ERROR", "Could not reach the location service");
  }
  if (!res.ok) {
    throw new ApiError(502, "UPSTREAM_ERROR", "The location service returned an error");
  }
  const body = (await res.json()) as Record<string, unknown>;
  const status = typeof body.status === "string" ? body.status : "UNKNOWN";
  // OK = results found; ZERO_RESULTS = a valid query that simply matched
  // nothing. Everything else (REQUEST_DENIED, OVER_QUERY_LIMIT, INVALID_REQUEST)
  // is an upstream/config problem, not the caller's fault — never echo Google's
  // raw error_message (it can leak key/config detail) to the client.
  if (status !== "OK" && status !== "ZERO_RESULTS") {
    throw new ApiError(502, "UPSTREAM_ERROR", "The location service is unavailable");
  }
  return body;
}

/** Address autocomplete. Returns [] for a query that matched nothing. */
export async function autocomplete(input: string, sessionToken?: string): Promise<PlaceSuggestion[]> {
  const trimmed = input.trim();
  if (trimmed.length === 0) return [];
  const params: Record<string, string> = { input: trimmed };
  if (sessionToken) params.sessiontoken = sessionToken;
  const body = await callGoogle("place/autocomplete/json", params);
  const predictions = Array.isArray(body.predictions) ? body.predictions : [];
  return predictions
    .map((p): PlaceSuggestion | null => {
      const pred = p as Record<string, unknown>;
      const placeId = typeof pred.place_id === "string" ? pred.place_id : null;
      const description = typeof pred.description === "string" ? pred.description : null;
      if (!placeId || !description) return null;
      return { placeId, description };
    })
    .filter((p): p is PlaceSuggestion => p !== null);
}

/** Resolve a place id to a formatted address + coordinates. */
export async function details(placeId: string, sessionToken?: string): Promise<PlaceLocation> {
  const params: Record<string, string> = { place_id: placeId, fields: "formatted_address,geometry" };
  if (sessionToken) params.sessiontoken = sessionToken;
  const body = await callGoogle("place/details/json", params);
  const result = body.result as Record<string, unknown> | undefined;
  const loc = parseLocation(result);
  if (!loc) throw Errors.notFound("Place");
  return loc;
}

/** Reverse-geocode a coordinate pair to a human address. null when none matched. */
export async function reverseGeocode(lat: number, lng: number): Promise<PlaceLocation | null> {
  const body = await callGoogle("geocode/json", { latlng: `${lat},${lng}` });
  const results = Array.isArray(body.results) ? body.results : [];
  if (results.length === 0) return null;
  const first = results[0] as Record<string, unknown>;
  const address = typeof first.formatted_address === "string" ? first.formatted_address : null;
  if (!address) return null;
  return { address, lat, lng };
}

function parseLocation(result: Record<string, unknown> | undefined): PlaceLocation | null {
  if (!result) return null;
  const address = typeof result.formatted_address === "string" ? result.formatted_address : null;
  const geometry = result.geometry as Record<string, unknown> | undefined;
  const location = geometry?.location as Record<string, unknown> | undefined;
  const lat = typeof location?.lat === "number" ? location.lat : null;
  const lng = typeof location?.lng === "number" ? location.lng : null;
  if (address === null || lat === null || lng === null) return null;
  return { address, lat, lng };
}

/**
 * Forward-geocode a free-text address into coordinates.
 *
 * The trip API is coordinate-based (the server computes the authoritative
 * distance and fare from them), so the app needs a way to obtain coordinates
 * when the device can't supply them — e.g. the rider denied location access, or
 * the map didn't load and there was no pin to drop. Without this the rider
 * simply cannot book, which is a dead end rather than a degraded experience.
 */
export async function forwardGeocode(query: string): Promise<PlaceLocation | null> {
  const body = await callGoogle("geocode/json", { address: query });
  const results = Array.isArray(body.results) ? body.results : [];
  return parseLocation(results[0] as Record<string, unknown> | undefined);
}
