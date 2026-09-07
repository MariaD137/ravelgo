import { Router } from "express";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { getAllDriverLocations, getRiderLocation, getLatestDriverLocation } from "../realtime/hub";

export const adminRouter = Router();

function fullName(u: { firstName: string; lastName: string } | null | undefined) {
  if (!u) return "";
  return `${u.firstName} ${u.lastName}`.trim();
}

// Active, in-progress trip/delivery statuses — a driver in one of these is
// "busy" on the map rather than available, and the job itself is drawn as a
// route. Matches TripStatus / CourierStatus in schema.prisma.
const ACTIVE_TRIP_STATUSES = ["MATCHED", "IN_PROGRESS"] as const;
const ACTIVE_COURIER_STATUSES = ["MATCHED", "PICKED_UP", "IN_TRANSIT"] as const;

// A location report older than this is no longer "live" for monitoring
// purposes. Set comfortably above every reporting cadence in the apps (the
// driver app's idle REST ping is every 20s, its mid-trip WebSocket push is
// every 5s; the rider app's trip ping is every 15s) so ordinary network
// jitter never flickers a fresh entity between LIVE and STALE.
const LIVE_LOCATION_THRESHOLD_MS = 30_000;

function locationFreshness(updatedAt: string): "LIVE" | "STALE" {
  return Date.now() - new Date(updatedAt).getTime() <= LIVE_LOCATION_THRESHOLD_MS ? "LIVE" : "STALE";
}

// Admin: the Live Map's data source. Every driver pin is a driver who has
// actually reported a coordinate (via the WebSocket location feed while
// mid-trip, or the REST ping in drivers.routes.ts while merely online/idle) —
// a driver who has never reported one simply isn't drawn, rather than being
// given a fabricated position. Marker colour is derived here, server-side,
// from real state (an open incident beats an active job beats being online):
//   GREEN available · BLUE on a passenger trip · ORANGE on a logistics job ·
//   RED open incident · GRAY known-but-currently-offline.
adminRouter.get("/admin/live-map", requireAuth, requireRole("Admin"), async (_req, res) => {
  const locations = getAllDriverLocations();
  const driverIds = locations.map((l) => l.driverId);
  const now = new Date();

  const [drivers, activeTrips, activeCourierRequests, openAlerts, activeRentalBookings] = await Promise.all([
    prisma.driver.findMany({
      where: { id: { in: driverIds } },
      include: { user: true, vehicles: { where: { isPrimary: true }, take: 1 } },
    }),
    prisma.trip.findMany({
      where: { status: { in: [...ACTIVE_TRIP_STATUSES] } },
      include: { rider: true, driver: { include: { user: true } }, payment: true },
    }),
    // Every active package, platform-wide — not just those whose courier has
    // a cached location — so the Packages view is complete even before that
    // courier's next location ping arrives.
    prisma.courierRequest.findMany({
      where: { status: { in: [...ACTIVE_COURIER_STATUSES] } },
      include: { sender: true, driver: { include: { user: true } } },
    }),
    prisma.emergencyAlert.findMany({
      where: { status: "OPEN" },
      include: { user: { include: { driverProfile: true } } },
    }),
    // "Live" rentals: a CONFIRMED booking whose date range covers today. No
    // GPS/telematics source exists anywhere in the rental data model (a
    // RentalListing is a driver's own vehicle listed for a self-drive
    // reservation, not a chauffeured or tracked ride) — see mapRentals below,
    // which deliberately never invents a coordinate for these.
    prisma.rentalBooking.findMany({
      where: { status: "CONFIRMED", startDate: { lte: now }, endDate: { gte: now } },
      include: { renter: true, listing: { include: { vehicle: true, driver: { include: { user: true } } } } },
    }),
  ]);

  const driverById = new Map(drivers.map((d) => [d.id, d]));
  const activeTripByDriver = new Map(activeTrips.filter((t) => t.driverId).map((t) => [t.driverId as string, t]));
  const logisticsDriverIds = new Set(
    activeCourierRequests.map((c) => c.driverId).filter((id): id is string => !!id),
  );
  const incidentDriverIds = new Set(
    openAlerts.map((a) => a.user.driverProfile?.id).filter((id): id is string => !!id),
  );

  const mapDrivers = locations
    .map((loc) => {
      const driver = driverById.get(loc.driverId);
      if (!driver) return null; // stale/offboarded driver id still cached in the in-memory hub
      const trip = activeTripByDriver.get(driver.id);
      const vehicle = driver.vehicles[0];

      let markerStatus: "AVAILABLE" | "ON_TRIP" | "LOGISTICS" | "OFFLINE" | "INCIDENT";
      if (incidentDriverIds.has(driver.id)) markerStatus = "INCIDENT";
      else if (trip) markerStatus = "ON_TRIP";
      else if (logisticsDriverIds.has(driver.id)) markerStatus = "LOGISTICS";
      else if (driver.isOnline) markerStatus = "AVAILABLE";
      else markerStatus = "OFFLINE";

      // A 3-way presence badge for the admin UI, distinct from markerStatus:
      // a driver can be nominally isOnline yet have gone dark (app killed,
      // network lost) without ever calling the offline toggle — OFFLINE here
      // always wins, but among online drivers, presence still tells the
      // truth about how fresh that pin actually is.
      const presence: "LIVE" | "STALE" | "OFFLINE" = !driver.isOnline ? "OFFLINE" : locationFreshness(loc.updatedAt);

      return {
        driverId: driver.id,
        name: fullName(driver.user),
        lat: loc.lat,
        lng: loc.lng,
        updatedAt: loc.updatedAt,
        markerStatus,
        presence,
        rating: driver.rating,
        vehicle: vehicle ? `${vehicle.brand} ${vehicle.model}`.trim() : null,
        activeTripId: trip?.id ?? null,
      };
    })
    .filter((d): d is NonNullable<typeof d> => d !== null);

  const mapTrips = activeTrips.map((t) => ({
    id: t.id,
    status: t.status,
    riderName: fullName(t.rider),
    driverName: t.driver ? fullName(t.driver.user) : null,
    pickup: t.pickup,
    destination: t.destination,
    pickupLat: t.pickupLat,
    pickupLng: t.pickupLng,
    dropoffLat: t.dropoffLat,
    dropoffLng: t.dropoffLng,
    fare: t.finalFare ?? t.estimatedFare,
    paymentMethod: t.payment?.method ?? null,
    paymentStatus: t.payment?.status ?? null,
  }));

  // Riders: one entry per active trip. The rider's live position comes ONLY
  // from POST /trips/:id/rider-location (the rider app's own real GPS
  // report) — never fabricated. Until that trip has received at least one
  // report, lat/lng/updatedAt/presence are simply omitted rather than
  // defaulted to anything.
  const mapRiders = activeTrips.map((t) => {
    const loc = getRiderLocation(t.id);
    return {
      tripId: t.id,
      riderName: fullName(t.rider),
      status: t.status,
      pickup: t.pickup,
      destination: t.destination,
      driverName: t.driver ? fullName(t.driver.user) : null,
      lat: loc?.lat ?? null,
      lng: loc?.lng ?? null,
      updatedAt: loc?.updatedAt ?? null,
      presence: loc ? locationFreshness(loc.updatedAt) : null,
    };
  });

  // Packages: "current courier location" reuses the SAME driver GPS feed as
  // the Drivers tab (no second tracking system) — a package has no location
  // of its own, only whichever driver is currently carrying it. No route
  // line is drawn: CourierRequest stores pickup/dropoff as free-text
  // addresses only, with no coordinates, and none are fabricated here.
  const mapPackages = activeCourierRequests.map((c) => {
    const loc = c.driverId ? getLatestDriverLocation(c.driverId) : undefined;
    return {
      id: c.id,
      senderName: fullName(c.sender),
      recipientName: c.recipientName,
      courierName: c.driver ? fullName(c.driver.user) : null,
      pickupAddress: c.pickupAddress,
      dropoffAddress: c.dropoffAddress,
      status: c.status,
      lat: loc?.lat ?? null,
      lng: loc?.lng ?? null,
      updatedAt: loc?.updatedAt ?? null,
      presence: loc ? locationFreshness(loc.updatedAt) : null,
    };
  });

  // Rentals: real lifecycle data (renter, vehicle, dates, status) only.
  // locationAvailable is always false — see the query comment above for why
  // no coordinate is ever attached to one of these.
  const mapRentals = activeRentalBookings.map((b) => ({
    id: b.id,
    vehicle: `${b.listing.vehicle.brand} ${b.listing.vehicle.model}`.trim(),
    plateNumber: b.listing.vehicle.plateNumber,
    renterName: fullName(b.renter),
    ownerName: fullName(b.listing.driver.user),
    startDate: b.startDate,
    endDate: b.endDate,
    status: b.status,
    locationAvailable: false,
  }));

  res.json({
    drivers: mapDrivers,
    trips: mapTrips,
    riders: mapRiders,
    packages: mapPackages,
    rentals: mapRentals,
    timestamp: new Date().toISOString(),
  });
});

const START_OF_TODAY = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};

// Admin: dashboard KPIs. Every figure here is a real aggregate query against
// the same tables the rest of the admin app reads — nothing is simulated.
adminRouter.get("/admin/dashboard", requireAuth, requireRole("Admin"), async (_req, res) => {
  const todayStart = START_OF_TODAY();

  const [
    activeTrips,
    onlineDrivers,
    driversOnTrip,
    pendingDocs,
    pendingCarPaddy,
    pendingRideRequests,
    activeLogisticsDeliveries,
    registeredRiders,
    todaysPayments,
  ] = await Promise.all([
    prisma.trip.count({ where: { status: { in: ["MATCHED", "IN_PROGRESS"] } } }),
    // "Online" now means approved AND currently online (see Driver.isOnline).
    prisma.driver.count({ where: { status: "ACTIVE", isOnline: true } }),
    prisma.driver.count({ where: { status: "ACTIVE", isOnline: true, tripsAsDriver: { some: { status: { in: ["MATCHED", "IN_PROGRESS"] } } } } }),
    prisma.driverDocument.count({ where: { status: "PENDING" } }),
    prisma.carPaddyRequest.count({ where: { status: { in: ["SUBMITTED", "IN_REVIEW"] } } }),
    prisma.trip.count({ where: { status: "REQUESTED" } }),
    prisma.courierRequest.count({ where: { status: { in: [...ACTIVE_COURIER_STATUSES] } } }),
    prisma.user.count({ where: { role: "RIDER" } }),
    prisma.payment.findMany({
      where: { status: "SUCCEEDED", paidAt: { gte: todayStart } },
      select: { amount: true, method: true },
    }),
  ]);

  let cashToday = 0;
  let cardToday = 0;
  let walletToday = 0;
  for (const p of todaysPayments) {
    if (p.method === "CASH") cashToday += p.amount;
    else if (p.method === "CARD") cardToday += p.amount;
    else if (p.method === "WALLET") walletToday += p.amount;
  }

  res.json({
    activeTrips,
    onlineDrivers,
    driversOnTrip,
    availableDrivers: Math.max(0, onlineDrivers - driversOnTrip),
    pendingApprovals: pendingDocs + pendingCarPaddy,
    pendingRideRequests,
    activeLogisticsDeliveries,
    registeredRiders,
    cashCollectedToday: cashToday,
    cardRevenueToday: cardToday,
    walletRevenueToday: walletToday,
  });
});

const MS_PER_DAY = 24 * 60 * 60 * 1000;

// Admin: real ride-revenue and completed-trips aggregates for the last 7
// days, bucketed by day. There's no tracked "driver online hours" anywhere
// in the schema, so that metric is intentionally not returned rather than
// fabricated — the admin UI should say so instead of showing a fake number.
adminRouter.get("/admin/analytics", requireAuth, requireRole("Admin"), async (_req, res) => {
  const days = 7;
  const end = new Date();
  end.setHours(0, 0, 0, 0);
  end.setDate(end.getDate() + 1); // exclusive upper bound: start of tomorrow
  const start = new Date(end.getTime() - days * MS_PER_DAY);

  const [payments, trips] = await Promise.all([
    prisma.payment.findMany({
      where: { status: "SUCCEEDED", paidAt: { gte: start, lt: end } },
      select: { amount: true, paidAt: true },
    }),
    prisma.trip.findMany({
      where: { status: "COMPLETED", completedAt: { gte: start, lt: end } },
      select: { completedAt: true },
    }),
  ]);

  const buckets = Array.from({ length: days }, (_, i) => {
    const date = new Date(start.getTime() + i * MS_PER_DAY);
    return { date: date.toISOString().slice(0, 10), revenue: 0, completedTrips: 0 };
  });
  const bucketIndex = (d: Date) => Math.floor((d.getTime() - start.getTime()) / MS_PER_DAY);

  for (const p of payments) {
    const idx = p.paidAt ? bucketIndex(p.paidAt) : -1;
    if (idx >= 0 && idx < days) buckets[idx].revenue += p.amount;
  }
  for (const t of trips) {
    const idx = t.completedAt ? bucketIndex(t.completedAt) : -1;
    if (idx >= 0 && idx < days) buckets[idx].completedTrips += 1;
  }

  res.json({ days: buckets });
});

// Admin: audit log of privileged actions, newest first.
adminRouter.get("/admin/audit", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [entries, total] = await Promise.all([
    prisma.auditLog.findMany({
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.auditLog.count(),
  ]);
  res.json(paginate(entries, total, page, pageSize));
});
