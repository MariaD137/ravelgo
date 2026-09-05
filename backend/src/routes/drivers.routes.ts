import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { recordAudit } from "../lib/audit";
import { cognitoGroups } from "../services/cognito";
import { sensitiveLimiter } from "../middleware/rate-limit";

export const driversRouter = Router();

const applyDriverSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phoneNumber: z.string().optional(),
  preferredLanguage: z.string().default("English"),
});

// Any authenticated user: apply to become a driver. This is the ONLY in-app
// path to the "Driver" role, and it is server-authoritative — the SERVER adds
// the caller to the Cognito "Driver" group using its own scoped IAM role; the
// client never touches group membership and cannot self-promote (P0 #2).
//
// The new profile is PENDING_REVIEW: being in the Driver group only lets the
// applicant manage their own profile and upload review documents/vehicles.
// Actually going online and being matched to trips stays gated on an admin
// approving the driver to ACTIVE (see /drivers/me/availability and
// services/matching.ts), so this endpoint grants no ability to earn on its own.
driversRouter.post("/drivers/apply", sensitiveLimiter, requireAuth, async (req, res) => {
  const parsed = applyDriverSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { preferredLanguage, ...userFields } = parsed.data;

  // Create/find the profile first (the application's source of truth). Both
  // upserts and the group add are idempotent, so a retry after a partial
  // failure converges rather than duplicating or corrupting anything.
  const user = await prisma.user.upsert({
    where: { cognitoSub: req.user!.sub },
    // On an EXISTING user only flip the role — never overwrite their stored
    // name/email from the application payload (the client may send placeholder
    // names, which must not clobber a real profile). New users are seeded with
    // the supplied fields.
    update: { role: "DRIVER" },
    create: { cognitoSub: req.user!.sub, role: "DRIVER", ...userFields },
  });

  const alreadyApplied = await prisma.driver.findUnique({ where: { userId: user.id } });
  const driver =
    alreadyApplied ??
    (await prisma.driver.create({ data: { userId: user.id, preferredLanguage } }));

  // Server-authoritative role grant. If Cognito rejects this the role would
  // not actually take effect, so surface it (502) rather than reporting a
  // success the caller can't use — the DB profile is left in place so a retry
  // simply re-adds the group (a no-op if it later succeeded).
  try {
    await cognitoGroups.addUserToGroup(req.user!.sub, "Driver");
  } catch (err) {
    console.error("Failed to add user to Driver group during application", err);
    return res.status(502).json({
      error: "Your driver application was saved but role activation failed. Please try again.",
    });
  }

  void recordAudit({
    actorSub: req.user!.sub,
    action: "DRIVER_APPLICATION_SUBMITTED",
    entityType: "Driver",
    entityId: driver.id,
    metadata: { status: driver.status },
  });

  res.status(alreadyApplied ? 200 : 201).json(driver);
});

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

// Driver: get my own profile
driversRouter.get("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { vehicles: true, documents: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  res.json(driver);
});

const availabilitySchema = z.object({ isOnline: z.boolean() });

// Driver: go online / offline. Only an ACTIVE (admin-approved) driver can go
// online; matching (services/matching.ts) only assigns trips to drivers who
// are both ACTIVE and online.
driversRouter.patch("/drivers/me/availability", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = availabilitySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  if (parsed.data.isOnline && driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account is not approved to go online yet." });
  }

  const updated = await prisma.driver.update({
    where: { id: driver.id },
    data: { isOnline: parsed.data.isOnline },
  });
  res.json(updated);
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
driversRouter.patch("/drivers/:id/status", requireAuth, requireAdminPermission("drivers:write"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "DRIVER_STATUS_CHANGED",
    entityType: "Driver",
    entityId: driver.id,
    metadata: { status: parsed.data.status },
  });
  res.json(driver);
});

// Driver: toggle online preference is handled client-side / via a lightweight presence
// table in a later iteration; ride matching (websocket/App Sync) is intentionally out
// of scope for this MVP skeleton.
