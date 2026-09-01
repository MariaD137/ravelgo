import { Router } from "express";
import { z } from "zod";
import { requireAuth } from "../middleware/auth";
import { placesLimiter } from "../middleware/rate-limit";
import { formatZodError } from "../lib/errors";
import { autocomplete, details, reverseGeocode } from "../services/places";

export const placesRouter = Router();

// All routes are authenticated: the proxy spends real Google quota, so only
// signed-in app users may drive it (this is the "bot" boundary — an anonymous
// caller can't burn the paid API).

const autocompleteSchema = z.object({
  q: z.string().min(1, "q is required").max(200),
  sessionToken: z.string().max(100).optional(),
});

// Address autocomplete for the ride/destination search box.
placesRouter.get("/places/autocomplete", placesLimiter, requireAuth, async (req, res, next) => {
  try {
    const parsed = autocompleteSchema.safeParse(req.query);
    if (!parsed.success) throw formatZodError(parsed.error);
    const suggestions = await autocomplete(parsed.data.q, parsed.data.sessionToken);
    res.json({ suggestions });
  } catch (err) {
    next(err);
  }
});

const detailsSchema = z.object({
  placeId: z.string().min(1, "placeId is required").max(400),
  sessionToken: z.string().max(100).optional(),
});

// Resolve a chosen suggestion to a formatted address + coordinates. The
// coordinates are what the client needs to price and request the trip.
placesRouter.get("/places/details", placesLimiter, requireAuth, async (req, res, next) => {
  try {
    const parsed = detailsSchema.safeParse(req.query);
    if (!parsed.success) throw formatZodError(parsed.error);
    const place = await details(parsed.data.placeId, parsed.data.sessionToken);
    res.json(place);
  } catch (err) {
    next(err);
  }
});

const reverseSchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
});

// Reverse-geocode the device's coordinates into a "From" address for the
// pickup line. Returns { address: null } when nothing matched so the client
// can fall back to showing the raw coordinates.
placesRouter.get("/geocode/reverse", placesLimiter, requireAuth, async (req, res, next) => {
  try {
    const parsed = reverseSchema.safeParse(req.query);
    if (!parsed.success) throw formatZodError(parsed.error);
    const place = await reverseGeocode(parsed.data.lat, parsed.data.lng);
    if (!place) return res.json({ address: null, lat: parsed.data.lat, lng: parsed.data.lng });
    res.json(place);
  } catch (err) {
    next(err);
  }
});
