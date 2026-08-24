import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { Errors } from "../lib/errors";
import { getOnlineHoursToday, setDriverOnline } from "../services/presence";
import { broadcastFleetEvent } from "../realtime/hub";
import { publicAssetUrl } from "../lib/assetUrl";
import { env } from "../config/env";
import { withBypass } from "../lib/rls";

export const driversRouter = Router();

// Admin: list all drivers
driversRouter.get("/drivers", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [drivers, total] = await Promise.all([
    prisma.driver.findMany({
      include: { user: true, vehicles: true },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.driver.count(),
  ]);
  res.json(paginate(drivers, total, page, pageSize));
}));

const createDriverSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phoneNumber: z.string().optional(),
  preferredLanguage: z.string().default("English"),
  quietModePreferred: z.boolean().default(false),
});

// Driver: create my profile (called once, right after Cognito sign-up completes
// the driver onboarding flow — Cognito itself has no Postgres row for the user)
driversRouter.post("/drivers/me", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = createDriverSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { preferredLanguage, quietModePreferred, ...userFields } = parsed.data;

  const user = await prisma.user.upsert({
    where: { cognitoSub: req.user!.sub },
    update: {},
    create: { cognitoSub: req.user!.sub, role: "DRIVER", ...userFields },
  });

  const driver = await prisma.driver.upsert({
    where: { userId: user.id },
    update: {},
    create: { userId: user.id, preferredLanguage, quietModePreferred },
  });

  res.status(201).json(driver);
}));

// Driver: get my own profile
driversRouter.get("/drivers/me", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  res.json(driver);
}));

const onlineSchema = z.object({ isOnline: z.boolean() });

// Driver: go online / offline. This is the authoritative presence toggle —
// the Flutter client must call this rather than only flipping local widget
// state, since the backend (not the app) is the source of truth for
// whether a driver is online, and it's what the admin fleet view and the
// driver's own online-hours summary are both computed from.
//
// Enforces the existing PENDING_REVIEW / ACTIVE / SUSPENDED approval state
// machine: only an ACTIVE driver may go online. SUSPENDED can still go
// offline (never trapped online), matching the emergency-suspend flow in
// PATCH /drivers/:id/status below.
driversRouter.patch("/drivers/me/online", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const parsed = onlineSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
    if (!driver) throw Errors.notFound("Driver profile");

    const updated = await setDriverOnline(driver.id, driver.status, parsed.data.isOnline);
    broadcastFleetEvent(updated.isOnline ? "driver:online" : "driver:offline", {
      driverId: updated.id,
      at: updated.lastOnlineAt!.toISOString(),
    });
    res.json(updated);
  } catch (err) {
    next(err);
  }
});

// Driver: daily dashboard summary — replaces what was hardcoded in the
// driver app's home screen (today's earnings, trips today, online hours).
// Every figure here is computed from persisted rows for the *calling*
// driver only (scoped by cognitoSub, same as GET /drivers/me above) —
// never accepts a driver id, so a driver can't read another driver's
// summary by guessing/changing one.
driversRouter.get("/drivers/me/summary", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
    if (!driver) throw Errors.notFound("Driver profile");

    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    // The driver isn't the Payment row's RLS owner (that's the paying
    // rider — see prisma/migrations/*_enable_rls_financial_tables), so a
    // plain query would silently see `payment: null` on every trip once
    // FORCE ROW LEVEL SECURITY is on. This bypass is safe: the real
    // authorization boundary is `driverId: driver.id` above — a driver
    // reading the total for their own completed trips, already scoped by
    // requireRole("Driver") + this filter.
    const tripsToday = await withBypass((tx) =>
      tx.trip.findMany({
        where: { driverId: driver.id, status: "COMPLETED", completedAt: { gte: startOfDay } },
        include: { payment: true },
      }),
    );

    const grossFareToday = tripsToday.reduce(
      (sum, trip) => sum + (trip.payment?.status === "SUCCEEDED" ? trip.payment.amount : 0),
      0,
    );
    const platformFeeToday = grossFareToday * env.PLATFORM_FEE_PERCENT;
    const netEarningsToday = grossFareToday - platformFeeToday;

    const onlineHoursToday = await getOnlineHoursToday(driver.id);

    res.json({
      isOnline: driver.isOnline,
      lastOnlineAt: driver.lastOnlineAt,
      tripsToday: tripsToday.length,
      grossFareToday,
      platformFeeToday,
      netEarningsToday,
      onlineHoursToday: Math.round(onlineHoursToday * 100) / 100,
      rating: driver.rating,
      totalTrips: driver.totalTrips,
    });
  } catch (err) {
    next(err);
  }
});

// Admin: get a single driver with their vehicles (each with photos),
// driver-level documents, and per-vehicle documents — everything the admin
// verification screen needs in one call.
// Registered after the literal "/drivers/me" routes above — Express matches
// path segments in registration order, so ":id" would otherwise swallow
// "me" and shadow the driver's own-profile routes with this Admin check.
driversRouter.get("/drivers/:id", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
  const driver = await prisma.driver.findUnique({
    where: { id: req.params.id },
    include: {
      user: true,
      vehicles: {
        include: { photos: { orderBy: { displayOrder: "asc" } }, documents: true },
        orderBy: { createdAt: "desc" },
      },
      // Driver-level documents only (license, background check) — a
      // vehicle-scoped document (registration, insurance) is already
      // nested under its own vehicle above, so it isn't duplicated here.
      documents: { where: { vehicleId: null } },
    },
  });
  if (!driver) return res.status(404).json({ error: "Driver not found" });

  res.json({
    ...driver,
    vehicles: driver.vehicles.map((vehicle) => ({
      ...vehicle,
      photos: vehicle.photos.map((photo) => ({ ...photo, url: publicAssetUrl(photo.fileKey) })),
    })),
  });
}));

const statusSchema = z.object({
  status: z.enum(["ACTIVE", "PENDING_REVIEW", "SUSPENDED"]),
});

// Admin: suspend / reactivate a driver
driversRouter.patch("/drivers/:id/status", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  let driver = await prisma.driver.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });

  // A driver being suspended can't be left showing "online" to the fleet
  // — force them offline through the same presence service used for a
  // driver's own toggle, so the online-hours session log stays correct.
  if (parsed.data.status === "SUSPENDED" && driver.isOnline) {
    driver = await setDriverOnline(driver.id, driver.status, false);
  }

  if (parsed.data.status === "SUSPENDED") {
    broadcastFleetEvent("driver:suspended", { driverId: driver.id });
  }

  res.json(driver);
}));

const preferencesSchema = z.object({
  preferredLanguage: z.string().min(1).optional(),
  quietModePreferred: z.boolean().optional(),
});

// Driver: update my preferences
driversRouter.patch("/drivers/me/preferences", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = preferencesSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const updated = await prisma.driver.update({
    where: { id: driver.id },
    data: parsed.data,
  });
  res.json(updated);
}));
