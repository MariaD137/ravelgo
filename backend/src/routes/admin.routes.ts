import { Router } from "express";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { getLatestDriverLocation } from "../realtime/hub";

export const adminRouter = Router();

// Admin: dashboard KPIs
adminRouter.get("/admin/dashboard", requireAuth, requireRole("Admin"), async (_req, res) => {
  const [activeTrips, onlineDrivers, pendingDocs, pendingCarPaddy] = await Promise.all([
    prisma.trip.count({ where: { status: { in: ["MATCHED", "IN_PROGRESS"] } } }),
    // isOnline is real, persisted presence (see PATCH /drivers/me/online) —
    // previously this counted `status: "ACTIVE"`, which is verification
    // approval, not presence, so an approved driver asleep at home counted
    // as "online". Fixed to count actual presence.
    prisma.driver.count({ where: { isOnline: true } }),
    prisma.driverDocument.count({ where: { status: "PENDING" } }),
    prisma.carPaddyRequest.count({ where: { status: { in: ["SUBMITTED", "IN_REVIEW"] } } }),
  ]);

  res.json({
    activeTrips,
    onlineDrivers,
    pendingApprovals: pendingDocs + pendingCarPaddy,
  });
});

// Admin: fleet-wide driver presence. Counts by verification status +
// presence, plus a per-driver list (identity, status, online state, since
// when, current trip if assigned, primary vehicle, last known location —
// "unavailable" rather than fabricated coordinates when the driver hasn't
// pushed one over the WebSocket location channel yet, see
// realtime/hub.ts's in-memory latestDriverLocation).
//
// Real-time delivery of the events this list would otherwise need polling
// for (driver:online/offline/suspended/trip_started/trip_completed) is
// available over the existing WebSocket — an Admin-authenticated socket
// sends {"type":"subscribe:fleet"} (see realtime/server.ts) — this REST
// endpoint is the same data as a point-in-time snapshot / initial load.
adminRouter.get("/admin/drivers/presence", requireAuth, requireRole("Admin"), async (_req, res) => {
  const [total, online, pendingReview, suspended, active, drivers] = await Promise.all([
    prisma.driver.count(),
    prisma.driver.count({ where: { isOnline: true } }),
    prisma.driver.count({ where: { status: "PENDING_REVIEW" } }),
    prisma.driver.count({ where: { status: "SUSPENDED" } }),
    prisma.driver.count({ where: { status: "ACTIVE" } }),
    prisma.driver.findMany({
      include: {
        user: { select: { firstName: true, lastName: true, email: true } },
        vehicles: { where: { isPrimary: true }, take: 1 },
        tripsAsDriver: {
          where: { status: { in: ["MATCHED", "IN_PROGRESS"] } },
          select: { id: true, status: true },
          take: 1,
        },
      },
      orderBy: [{ isOnline: "desc" }, { lastOnlineAt: "desc" }],
    }),
  ]);

  res.json({
    counts: { total, online, offline: total - online, active, pendingReview, suspended },
    drivers: drivers.map((d) => {
      const location = getLatestDriverLocation(d.id);
      return {
        id: d.id,
        name: `${d.user.firstName} ${d.user.lastName}`,
        email: d.user.email,
        status: d.status,
        isOnline: d.isOnline,
        onlineSince: d.isOnline ? d.lastOnlineAt : null,
        currentTrip: d.tripsAsDriver[0] ?? null,
        vehicle: d.vehicles[0]
          ? `${d.vehicles[0].brand} ${d.vehicles[0].model} (${d.vehicles[0].plateNumber})`
          : null,
        location: location ? { lat: location.lat, lng: location.lng, updatedAt: location.updatedAt } : "Location unavailable",
      };
    }),
  });
});
