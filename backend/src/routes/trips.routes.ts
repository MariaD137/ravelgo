import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { blockIfAdminLacksPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { csvList, inFilter, paginate, paginationQuerySchema } from "../lib/pagination";
import {
  broadcastTripStatus,
  clearRiderLocation,
  getLatestDriverLocation,
  locationFreshness,
  recordRiderLocation,
} from "../realtime/hub";
import { notifyAllAdmins, notifyUser } from "../lib/notifications";
import { acceptTripOffer, declineTripOffer, matchDriverToTrip } from "../services/matching";
import { driverHasActiveDelivery } from "../lib/driver-conflicts";
import { quoteFare, quoteFareForCategory } from "../services/pricing";
import { MAX_FINAL_FARE_MULTIPLIER, MIN_FINAL_FARE_MULTIPLIER, moneyAmountSchema } from "../lib/money";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { estimateDurationMinutes, haversineKm, isValidCoordinate, MAX_TRIP_DISTANCE_KM } from "../lib/geo";
import { driverMayTransition, isValidTransition, riderMayCancel } from "../services/trip-status";
import { serializeTrip } from "../lib/trip-view";
import { computeRideWaitingCharge, getPricingPolicy } from "../lib/pricing-policy";
import { recordDriverCompensationCharge } from "../services/ledger";

export const tripsRouter = Router();

// A rider's live position is only meaningful, and only ever accepted, once a
// driver is assigned (MATCHED) through the ride itself (IN_PROGRESS) — before
// that there's nothing for ops to monitor, matching the admin Live Map's own
// ACTIVE_TRIP_STATUSES filter (admin.routes.ts).
const RIDER_TRACKABLE_STATUSES = ["MATCHED", "IN_PROGRESS"] as const;
const TERMINAL_TRIP_STATUSES = ["COMPLETED", "CANCELLED", "DISPUTED"] as const;

// The rider supplies pickup + dropoff COORDINATES (and display strings) — never
// the distance or the fare. The server computes the great-circle distance from
// the coordinates (lib/geo.ts) and the fare from the active PricingRule
// (services/pricing.ts), so a client can neither assert `estimatedFare: 1` nor
// post `distanceKm: 0` to collapse the fare (P0 #10). `distanceKm`/`duration`
// in the body, if present, are ignored.
const coord = z.number().finite();
const createTripSchema = z.object({
  pickup: z.string().min(1),
  destination: z.string().min(1),
  pickupLat: coord.min(-90).max(90),
  pickupLng: coord.min(-180).max(180),
  dropoffLat: coord.min(-90).max(90),
  dropoffLng: coord.min(-180).max(180),
  zone: z.string().min(1).optional(),
  category: z.string().default("Personal"),
  // The ride tier (RideCategory.key, e.g. "SWIFT") — optional so an older
  // client build that predates categories still works exactly as before,
  // pricing off the single active PricingRule via quoteFare().
  rideCategoryKey: z.string().optional(),
  pickupNote: z.string().optional(),
});

// Rider: request a trip
tripsRouter.post("/trips", sensitiveLimiter, requireAuth, requireRole("Rider"), async (req, res, next) => {
  const parsed = createTripSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { pickupLat, pickupLng, dropoffLat, dropoffLng } = parsed.data;
  const from = { lat: pickupLat, lng: pickupLng };
  const to = { lat: dropoffLat, lng: dropoffLng };
  if (!isValidCoordinate(from) || !isValidCoordinate(to)) {
    return res.status(400).json({ error: "Invalid pickup or dropoff coordinates" });
  }

  // Authoritative distance + duration, computed server-side from coordinates.
  const distanceKm = haversineKm(from, to);
  if (distanceKm > MAX_TRIP_DISTANCE_KM) {
    return res.status(400).json({ error: "Trip distance exceeds the serviceable maximum" });
  }
  const durationMinutes = estimateDurationMinutes(distanceKm);

  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider not found" });

  // Authoritative fare — never taken from the request body. A rideCategoryKey
  // prices off that category's own rate card; otherwise falls back to the
  // single active PricingRule, unchanged from before categories existed.
  let estimatedFare: number;
  if (parsed.data.rideCategoryKey) {
    const category = await prisma.rideCategory.findUnique({ where: { key: parsed.data.rideCategoryKey } });
    if (!category || !category.active) {
      return res.status(400).json({ error: "Unknown or inactive ride category" });
    }
    const fare = await quoteFareForCategory(category, distanceKm, durationMinutes, parsed.data.zone);
    estimatedFare = fare.estimatedFare;
  } else {
    try {
      const fare = await quoteFare(distanceKm, durationMinutes, parsed.data.zone);
      estimatedFare = fare.estimatedFare;
    } catch (err) {
      return next(err); // 409 when no active pricing rule is configured
    }
  }

  const trip = await prisma.trip.create({
    data: {
      pickup: parsed.data.pickup,
      destination: parsed.data.destination,
      pickupLat,
      pickupLng,
      dropoffLat,
      dropoffLng,
      distanceKm,
      category: parsed.data.category,
      rideCategoryKey: parsed.data.rideCategoryKey,
      pickupNote: parsed.data.pickupNote,
      estimatedFare,
      riderId: rider.id,
    },
  });

  // Offers the trip to one eligible driver (status -> OFFERED) — it is NOT
  // yet MATCHED, and the rider is not told "driver assigned" until that
  // driver actually calls POST /trips/:id/accept (see services/matching.ts).
  // Nothing here fakes an acceptance the driver hasn't given.
  const offered = await matchDriverToTrip(trip.id);
  res.status(201).json(serializeTrip(offered ?? trip));
});

// Rider or Driver: list the trips I'm party to (as the rider, or as the
// assigned driver). This is what powers a rider's trip history and a driver's
// completed-trips list. Declared before "/trips/:id" so "mine" isn't captured
// as an :id.
tripsRouter.get("/trips/mine", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const where = {
    OR: [
      { rider: { cognitoSub: req.user!.sub } },
      { driver: { user: { cognitoSub: req.user!.sub } } },
    ],
  };

  const [trips, total] = await Promise.all([
    prisma.trip.findMany({
      where,
      include: { rider: true, driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.trip.count({ where }),
  ]);
  res.json(paginate(trips.map(serializeTrip), total, page, pageSize));
});

const rateSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).optional(),
});

// Rider: rate the driver for a completed trip they own. Recomputes the
// driver's average rating across all their rated trips.
tripsRouter.post("/trips/:id/rating", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = rateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.rider.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to rate this trip" });
  }
  if (trip.status !== "COMPLETED") {
    return res.status(409).json({ error: "You can only rate a completed trip" });
  }
  if (!trip.driverId) {
    return res.status(409).json({ error: "This trip had no driver to rate" });
  }

  const updated = await prisma.trip.update({
    where: { id: trip.id },
    // The request schema has accepted an optional `comment` since this route
    // was written, but it was never persisted — silently discarding input a
    // rider explicitly submitted. Stored now so the driver's My Ratings
    // screen can show real feedback instead of nothing.
    data: { riderRating: parsed.data.rating, riderComment: parsed.data.comment ?? null },
  });

  // Recompute the driver's average rating from all their rated trips.
  const agg = await prisma.trip.aggregate({
    where: { driverId: trip.driverId, riderRating: { not: null } },
    _avg: { riderRating: true },
  });
  if (agg._avg.riderRating != null) {
    await prisma.driver.update({
      where: { id: trip.driverId },
      data: { rating: agg._avg.riderRating },
    });
  }

  res.json(updated);
});

// Rider or Driver: view a trip they're party to
tripsRouter.get("/trips/:id", requireAuth, async (req, res) => {
  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true, driver: { include: { user: true } }, payment: true },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const groups = req.user!.groups;
  const isAdmin = groups.includes("Admin");
  const isOwner =
    trip.rider.cognitoSub === req.user!.sub || trip.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !isAdmin) {
    return res.status(403).json({ error: "Not authorized to view this trip" });
  }
  const body = serializeTrip(trip);
  // Payment state is attached for Admin and for the trip's own rider/driver —
  // isOwner is already verified above. serializeTrip stays minimal for the
  // "mine" list (payments.routes.ts, an authoritative payment history, is
  // the right place for THAT; this single-trip detail route is what the
  // e-receipt screen fetches, and needs real method/status/amount/paidAt).
  res.json(isOwner || isAdmin ? { ...body, payment: trip.payment ?? null } : body);
});

// Driver assigned to it: report physical arrival at the pickup point.
// Anchors the free-waiting-period clock (lib/pricing-policy.ts) — set once,
// ignored on a repeat call so a flaky retry can never push the clock forward.
tripsRouter.post("/trips/:id/arrived", requireAuth, requireRole("Driver"), async (req, res) => {
  const existing = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Trip not found" });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver || existing.driverId !== driver.id) {
    return res.status(403).json({ error: "Not authorized to update this trip" });
  }
  if (existing.status !== "MATCHED") {
    return res.status(409).json({ error: "Can only report arrival for a matched trip" });
  }

  if (!existing.arrivedAt) {
    const trip = await prisma.trip.update({
      where: { id: existing.id },
      data: { arrivedAt: new Date() },
      include: { rider: true },
    });
    // EI-1 gap closed: the rider previously had no way to know the driver had
    // physically arrived, on the app's own strongest signal for it.
    await notifyUser(
      trip.riderId,
      "RIDE_DRIVER_ARRIVED",
      "Your driver has arrived",
      "Your driver is waiting at the pickup point.",
      { type: "TRIP", id: trip.id },
    );
    return res.json(serializeTrip(trip));
  }
  res.json(serializeTrip(existing));
});

// Driver: accept a trip that has been OFFERED to them. Server-authoritative
// (P0 special requirement) — this is the ONLY way a trip moves OFFERED ->
// MATCHED; nothing accepts on the driver's behalf, and the underlying update
// is atomic (services/matching.ts#acceptTripOffer) so two concurrent accept
// calls, or an accept racing a decline/expiry, can only ever have one winner.
tripsRouter.post("/trips/:id/accept", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  if (await driverHasActiveDelivery(driver.id)) {
    return res.status(409).json({
      error: "You're already carrying an active delivery. Finish or hand it off before accepting a ride.",
    });
  }

  const trip = await acceptTripOffer(req.params.id, driver.id);
  if (!trip) {
    return res.status(409).json({
      error: {
        code: "OFFER_NO_LONGER_AVAILABLE",
        message: "This ride offer is no longer available. It may have expired or already been resolved.",
        timestamp: new Date().toISOString(),
      },
    });
  }
  res.json(serializeTrip(trip));
});

// Driver: decline a trip that has been OFFERED to them. Per the P0 special
// requirement, this must NEVER cancel the rider's trip — it releases the
// offer back to the pool and the matching engine immediately tries the next
// eligible driver (excluding this one, permanently, for this trip).
tripsRouter.post("/trips/:id/decline", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const declined = await declineTripOffer(req.params.id, driver.id);
  if (!declined) {
    return res.status(409).json({
      error: {
        code: "OFFER_NO_LONGER_AVAILABLE",
        message: "This ride offer is no longer available. It may have expired or already been resolved.",
        timestamp: new Date().toISOString(),
      },
    });
  }
  res.status(204).send();
});

const updateStatusSchema = z.object({
  status: z.enum(["MATCHED", "IN_PROGRESS", "COMPLETED", "CANCELLED", "DISPUTED"]),
  finalFare: moneyAmountSchema.optional(),
});

// Driver assigned to it, or Admin: advance trip status (accept, start, complete)
tripsRouter.patch("/trips/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.trip.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Trip not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
    if (!driver || existing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to update this trip" });
    }
  } else if (await blockIfAdminLacksPermission(req, res, "drivers:write")) {
    return; // 403 already written
  }

  // Enforce the state machine (P0 #9): the backend is authoritative about which
  // status can follow which. This blocks REQUESTED→COMPLETED (billing a trip
  // never driven), COMPLETED→IN_PROGRESS (resurrecting a finished trip), and
  // reviving a CANCELLED trip. Admins are still bounded by the matrix but may
  // drive dispute transitions a driver cannot.
  if (!isValidTransition(existing.status, parsed.data.status)) {
    return res.status(409).json({
      error: {
        code: "INVALID_TRIP_TRANSITION",
        message: `Cannot move a trip from ${existing.status} to ${parsed.data.status}`,
        timestamp: new Date().toISOString(),
      },
    });
  }
  if (!isAdmin && !driverMayTransition(existing.status, parsed.data.status)) {
    return res.status(403).json({ error: "A driver may not perform this trip transition" });
  }

  // The final fare is what actually gets charged (payments.routes.ts) and
  // paid out (services/payouts.ts). It's set by the driver, so it must be
  // anchored to the server-computed estimate rather than trusted outright:
  // a driver can adjust up for waiting time / a longer route, but not to an
  // arbitrary multiple of the price the rider agreed to. An Admin (dispute
  // resolution, manual correction) is allowed to override outside the band.
  if (parsed.data.finalFare != null && !isAdmin) {
    const lower = existing.estimatedFare * MIN_FINAL_FARE_MULTIPLIER;
    const upper = existing.estimatedFare * MAX_FINAL_FARE_MULTIPLIER;
    if (parsed.data.finalFare < lower || parsed.data.finalFare > upper) {
      return res.status(422).json({
        error: {
          code: "FARE_OUT_OF_RANGE",
          message: `finalFare must be within ${MIN_FINAL_FARE_MULTIPLIER}x–${MAX_FINAL_FARE_MULTIPLIER}x the estimated fare of ${existing.estimatedFare}`,
          timestamp: new Date().toISOString(),
        },
      });
    }
  }

  const trip = await prisma.trip.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      finalFare: parsed.data.finalFare,
      completedAt: parsed.data.status === "COMPLETED" ? new Date() : undefined,
    },
    include: { rider: true, driver: { include: { user: true, vehicles: true } } },
  });
  if (isAdmin) {
    await recordAudit({
      actorSub: req.user!.sub,
      action: "TRIP_STATUS_OVERRIDDEN",
      entityType: "Trip",
      entityId: trip.id,
      metadata: { status: parsed.data.status, finalFare: parsed.data.finalFare },
    });
  }
  if (TERMINAL_TRIP_STATUSES.includes(trip.status as (typeof TERMINAL_TRIP_STATUSES)[number])) {
    clearRiderLocation(trip.id);
  }
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  if (trip.status === "IN_PROGRESS") {
    // Lock in the waiting charge now, from the real arrivedAt timestamp — the
    // one moment this is knowable, since the trip is about to actually start.
    // 100% driver-compensation, not commissioned (see services/commission.ts).
    if (trip.arrivedAt && trip.driverId) {
      const policy = await getPricingPolicy();
      const waitingCharge = computeRideWaitingCharge(policy, trip.arrivedAt);
      if (waitingCharge > 0) {
        await prisma.trip.update({ where: { id: trip.id }, data: { waitingCharge } });
        await recordDriverCompensationCharge({
          type: "WAITING_CHARGE",
          tripId: trip.id,
          customerId: trip.riderId,
          driverId: trip.driverId,
          amount: waitingCharge,
        });
      }
    }
    await notifyUser(trip.riderId, "RIDE_STARTED", "Ride started", "Your ride is now under way.", {
      type: "TRIP",
      id: trip.id,
    });
  } else if (trip.status === "COMPLETED") {
    await notifyUser(trip.riderId, "RIDE_COMPLETED", "Ride completed", "Your ride has been completed.", {
      type: "TRIP",
      id: trip.id,
    });
    // EI-1: the driver side of this event was previously silent — only the
    // rider was ever told a trip they were both on had completed. The driver
    // app has no other UI moment that surfaces the exact fare they earned,
    // so this doubles as their receipt for the trip, not just a courtesy ping.
    if (trip.driver) {
      const fare = trip.finalFare ?? trip.estimatedFare;
      await notifyUser(
        trip.driver.user.id,
        "RIDE_COMPLETED",
        "Trip completed",
        `You earned ${fare} for this trip.`,
        { type: "TRIP", id: trip.id },
      );
    }
    // EI-1: give admins a truthful, queryable record that this trip actually
    // reached COMPLETED — not just the override case below, which only fires
    // when an admin themself changed the status. actorSub is whoever actually
    // called this endpoint (the driver, in the normal path), so the log shows
    // who completed it, not just that it happened.
    await recordAudit({
      actorSub: req.user!.sub,
      action: "TRIP_COMPLETED",
      entityType: "Trip",
      entityId: trip.id,
      metadata: { finalFare: trip.finalFare, driverId: trip.driverId, riderId: trip.riderId },
    });
  } else if (trip.status === "CANCELLED") {
    await notifyUser(trip.riderId, "RIDE_CANCELLED", "Ride cancelled", "Your ride was cancelled.", {
      type: "TRIP",
      id: trip.id,
    });
  } else if (trip.status === "DISPUTED") {
    await notifyAllAdmins(
      "ADMIN_TRIP_DISPUTED",
      "Trip disputed",
      `Trip ${trip.id} was marked as disputed and needs review.`,
      { type: "TRIP", id: trip.id },
    );
  }
  res.json(serializeTrip(trip));
});

// Rider: cancel a trip they own, before it is under way (P0 #7). The rider app
// used to only navigate home — the trip stayed live and a driver could still
// be dispatched to someone who believed they had cancelled. This is the
// authoritative, ownership-checked cancel path; the status-PATCH route above
// stays Driver/Admin-only.
tripsRouter.post("/trips/:id/cancel", requireAuth, requireRole("Rider"), async (req, res) => {
  const existing = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true },
  });
  if (!existing) return res.status(404).json({ error: "Trip not found" });
  if (existing.rider.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to cancel this trip" });
  }
  if (!riderMayCancel(existing.status)) {
    return res.status(409).json({
      error: {
        code: "TRIP_NOT_CANCELLABLE",
        message: `A ${existing.status} trip can no longer be cancelled`,
        timestamp: new Date().toISOString(),
      },
    });
  }

  // A cancellation fee applies only once a driver is actually assigned and
  // dispatched (MATCHED) — cancelling a still-REQUESTED trip never cost
  // anyone anything — and only past the configured grace period. There is no
  // separate "matchedAt" timestamp, so requestedAt is used as the elapsed-time
  // anchor; in practice matching happens within seconds of the request, so
  // this is a close enough proxy for "how long has a driver been committed."
  let cancellationFee = 0;
  if (existing.status === "MATCHED" && existing.driverId) {
    const policy = await getPricingPolicy();
    const elapsedSec = (Date.now() - existing.requestedAt.getTime()) / 1000;
    if (elapsedSec > policy.rideCancellationGraceSec) {
      cancellationFee = policy.rideCancellationFee;
    }
  }

  const trip = await prisma.trip.update({
    where: { id: existing.id },
    data: { status: "CANCELLED", cancellationFee: cancellationFee > 0 ? cancellationFee : undefined },
    include: { rider: true, driver: { include: { user: true, vehicles: true } } },
  });
  if (cancellationFee > 0 && trip.driverId) {
    await recordDriverCompensationCharge({
      type: "CANCELLATION_FEE",
      tripId: trip.id,
      customerId: trip.riderId,
      driverId: trip.driverId,
      amount: cancellationFee,
    });
  }
  clearRiderLocation(trip.id);
  broadcastTripStatus(trip.id, trip.status, trip.finalFare);
  await notifyUser(trip.riderId, "RIDE_CANCELLED", "Ride cancelled", "Your ride was cancelled.", {
    type: "TRIP",
    id: trip.id,
  });
  // A driver may already be OFFERED or MATCHED when the rider cancels — they
  // need to know it's off, the same as courier.routes.ts's equivalent path
  // already notifies an assigned courier on a sender-initiated cancellation.
  if (trip.driver) {
    await notifyUser(trip.driver.user.id, "RIDE_CANCELLED", "Ride cancelled", "The rider cancelled this ride.", {
      type: "TRIP",
      id: trip.id,
    });
  }
  res.json(serializeTrip(trip));
});

// Rider or Driver: poll the assigned driver's last known location (a
// fallback for clients not holding a live WebSocket connection — see
// docs/realtime-architecture.md). 404s until the driver has sent at least
// one location update over WS.
tripsRouter.get("/trips/:id/driver-location", requireAuth, async (req, res) => {
  const trip = await prisma.trip.findUnique({
    where: { id: req.params.id },
    include: { rider: true, driver: { include: { user: true } } },
  });
  if (!trip) return res.status(404).json({ error: "Trip not found" });

  const groups = req.user!.groups;
  const isOwner =
    trip.rider.cognitoSub === req.user!.sub || trip.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !groups.includes("Admin")) {
    return res.status(403).json({ error: "Not authorized to view this trip" });
  }

  if (!trip.driverId) return res.status(404).json({ error: "No driver assigned yet" });
  const location = getLatestDriverLocation(trip.driverId);
  if (!location) return res.status(404).json({ error: "No location reported yet" });
  // EI-2: the same LIVE/STALE freshness model the admin Live Map and the
  // customer delivery-tracking screen already use (locationFreshness), so a
  // rider watching their driver on the map sees "live" mean the same thing
  // it means everywhere else this is shown — never a stale fix presented as
  // current.
  res.json({ ...location, presence: locationFreshness(location.updatedAt) });
});

const riderLocationSchema = z.object({
  lat: z.number().finite().gte(-90).lte(90),
  lng: z.number().finite().gte(-180).lte(180),
});

// Rider (owner only): report my current position for this trip. Mirrors
// POST /drivers/me/location's REST-ping pattern exactly, just scoped to one
// trip instead of "while online" — this is what backs the admin Live Map's
// Riders view. Only accepted while a driver is assigned or the ride is under
// way (never before matching, never after — see TERMINAL_TRIP_STATUSES
// above, which clears the cached position once the trip ends).
tripsRouter.post("/trips/:id/rider-location", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = riderLocationSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const trip = await prisma.trip.findUnique({ where: { id: req.params.id }, include: { rider: true } });
  if (!trip) return res.status(404).json({ error: "Trip not found" });
  if (trip.rider.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to report location for this trip" });
  }
  if (!RIDER_TRACKABLE_STATUSES.includes(trip.status as (typeof RIDER_TRACKABLE_STATUSES)[number])) {
    return res.status(409).json({ error: "This trip isn't currently trackable." });
  }

  const location = recordRiderLocation(trip.id, parsed.data.lat, parsed.data.lng);
  res.json(location);
});

const adminTripsQuerySchema = paginationQuerySchema.extend({
  // Optional server-side status filter, comma-separated (?status=MATCHED,IN_PROGRESS)
  // so the Admin App's multi-select chips narrow the whole table, not one page.
  status: z.preprocess(
    csvList,
    z.array(z.enum(["REQUESTED", "OFFERED", "MATCHED", "IN_PROGRESS", "COMPLETED", "CANCELLED", "DISPUTED"])).optional(),
  ),
});

// Admin: monitor all trips
tripsRouter.get("/trips", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = adminTripsQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, status } = parsed.data;
  const where = { status: inFilter(status) };

  const [trips, total] = await Promise.all([
    prisma.trip.findMany({
      where,
      include: { rider: true, driver: { include: { user: true } }, payment: true },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.trip.count({ where }),
  ]);
  // Admin-only route, so payment state is always safe to attach here.
  const serialized = trips.map((t) => (t.payment ? { ...serializeTrip(t), payment: t.payment } : serializeTrip(t)));
  res.json(paginate(serialized, total, page, pageSize));
});
