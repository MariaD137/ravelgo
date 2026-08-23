import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const driversRouter = Router();

// Admin: list all drivers
driversRouter.get("/drivers", requireAuth, requireRole("Admin"), async (req, res) => {
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
});

const createDriverSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phoneNumber: z.string().optional(),
  preferredLanguage: z.string().default("English"),
});

// Driver: create my profile (called once, right after Cognito sign-up completes
// the driver onboarding flow — Cognito itself has no Postgres row for the user)
driversRouter.post("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createDriverSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { preferredLanguage, ...userFields } = parsed.data;

  const user = await prisma.user.upsert({
    where: { cognitoSub: req.user!.sub },
    update: {},
    create: { cognitoSub: req.user!.sub, role: "DRIVER", ...userFields },
  });

  const driver = await prisma.driver.upsert({
    where: { userId: user.id },
    update: {},
    create: { userId: user.id, preferredLanguage },
  });

  res.status(201).json(driver);
});

// Driver: get my own profile. Includes `user` (name/email/phone live there,
// not on Driver itself) — previously omitted, which meant a driver's own
// profile screen had no real name/email/phone to render at all and fell
// back to hardcoded placeholder data.
driversRouter.get("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { user: true, vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  res.json(driver);
});

const onlineSchema = z.object({ online: z.boolean() });

// Driver: go online/offline. This is the real-time presence signal
// matching.ts requires (online: true) alongside status: "ACTIVE" before a
// driver is matching-eligible — replaces the previous MVP-skeleton
// placeholder where this toggle only existed in the Flutter app's own
// local state and had no effect on the backend at all.
driversRouter.patch("/drivers/me/online", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = onlineSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { count } = await prisma.driver.updateMany({
    where: { user: { cognitoSub: req.user!.sub } },
    data: { online: parsed.data.online },
  });
  if (count === 0) return res.status(404).json({ error: "Driver profile not found" });

  const driver = await prisma.driver.findFirstOrThrow({ where: { user: { cognitoSub: req.user!.sub } } });
  res.json(driver);
});

const updateMeSchema = z.object({
  preferredLanguage: z.string().min(1).optional(),
  quietModePreferred: z.boolean().optional(),
});

// Driver: update my own ride-matching preferences (preferredLanguage,
// quietModePreferred — the two Driver-model fields the app's "Ride
// Preferences" screen can actually persist). Mirrors PATCH /riders/me's
// conditional-updateMany pattern: POST /drivers/me only ever sets
// preferredLanguage once, at onboarding, and there was previously no way to
// change it (or quietModePreferred) afterward.
driversRouter.patch("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateMeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { count } = await prisma.driver.updateMany({
    where: { user: { cognitoSub: req.user!.sub } },
    data: parsed.data,
  });
  if (count === 0) return res.status(404).json({ error: "Driver profile not found" });

  const driver = await prisma.driver.findFirstOrThrow({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { user: true, vehicles: true, documents: true },
  });
  res.json(driver);
});

// Driver: my current active assignment (Ride, Courier, or Rental), if any.
// The primary polling mechanism driver_app uses to discover it has been
// matched to a new trip — matching itself is fully server-side and
// synchronous (services/matching.ts), so the driver has no "browse and
// accept" step to learn about it from; this is how they find out. A
// best-effort WebSocket push (driver:assignment, see realtime/server.ts)
// overlays this same polling loop for near-instant delivery, exactly
// mirroring how RideSession drives the rider side in user_app.
driversRouter.get("/drivers/me/assignment", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const assignment = await prisma.driverAssignment.findFirst({
    where: { driverId: driver.id, status: "ACTIVE" },
  });
  res.json(assignment);
});

// Admin: get a single driver with documents.
// Registered after the literal "/drivers/me" routes above — Express matches
// path segments in registration order, so ":id" would otherwise swallow
// "me" and shadow the driver's own-profile routes with this Admin check.
driversRouter.get("/drivers/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const driver = await prisma.driver.findUnique({
    where: { id: req.params.id },
    include: { user: true, vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver not found" });
  res.json(driver);
});

const statusSchema = z.object({
  status: z.enum(["ACTIVE", "PENDING_REVIEW", "SUSPENDED"]),
});

// Admin: suspend / reactivate a driver
driversRouter.patch("/drivers/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  res.json(driver);
});
