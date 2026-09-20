import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { recordAudit } from "../lib/audit";
import { cognitoGroups } from "../services/cognito";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { recordDriverLocation } from "../realtime/hub";
import { matchPendingTrips } from "../services/matching";
import { notifyUser } from "../lib/notifications";

// Same pattern as courier.routes.ts's withProofUrls: a dedicated S3 client for
// signing GET URLs to objects in the private documents bucket. Kept
// per-route-file like the existing S3 clients elsewhere (courier.routes.ts,
// uploads.routes.ts) rather than introducing a new shared module.
const s3 = new S3Client({ region: env.AWS_REGION });
const DOCUMENT_URL_EXPIRY_SECONDS = 300;

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

const DRIVER_STATUSES = ["ACTIVE", "PENDING_REVIEW", "SUSPENDED"] as const;

const listDriversQuerySchema = paginationQuerySchema.extend({
  // Optional server-side filter on Driver.status. The Admin App's pending-
  // applications view previously filtered client-side over the first page
  // only, so a PENDING_REVIEW driver past the pagination window was simply
  // invisible to reviewers; filtering here makes "show me every driver still
  // waiting" a real query over the whole table.
  status: z.enum(DRIVER_STATUSES).optional(),
});

// Admin: list all drivers (optionally narrowed to one status)
driversRouter.get("/drivers", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = listDriversQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, status } = parsed.data;
  const where = status ? { status } : {};

  const [drivers, total] = await Promise.all([
    prisma.driver.findMany({
      where,
      include: { user: true, vehicles: true },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.driver.count({ where }),
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

const updateDriverMeSchema = z
  .object({ phoneNumber: z.string().min(1) })
  .refine((data) => Object.keys(data).length > 0, "At least one field is required");

// Driver: update my own contact details. Mirrors riders.routes.ts's
// PATCH /riders/me — phoneNumber lives on User, not Driver, so this updates
// the User row via the driver's own Cognito sub. Only phoneNumber for now;
// name/email stay tied to the Cognito identity used to sign in.
driversRouter.patch("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateDriverMeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.update({
    where: { cognitoSub: req.user!.sub },
    data: parsed.data,
  });
  res.json({ phoneNumber: user.phoneNumber });
});

const updateDriverPreferencesSchema = z
  .object({
    preferredLanguage: z.string().min(1),
    quietModePreferred: z.boolean(),
  })
  .partial()
  .refine((data) => Object.keys(data).length > 0, "At least one field is required");

// Driver: update my ride preferences. Both fields already existed on the
// Driver model (preferredLanguage set once at onboarding/application;
// quietModePreferred was written by neither route — a dead column until
// now) but there was no way to change either after onboarding.
driversRouter.patch("/drivers/me/preferences", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateDriverPreferencesSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const updated = await prisma.driver.update({ where: { id: driver.id }, data: parsed.data });
  res.json(updated);
});

// Driver: get my own profile
driversRouter.get("/drivers/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    include: { vehicles: true, documents: true, user: { select: { phoneNumber: true } } },
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
  // A recent rider request that found nobody online at the time stays
  // REQUESTED forever otherwise (matching only ever runs once, synchronously,
  // at request time — see services/matching.ts). This is the moment that
  // changes, so it's the right place to retry, not a blind poll. Awaited
  // (like recordAudit elsewhere) so a caller can never observe isOnline:
  // true before a match that should already exist actually does; a failure
  // here must never turn a successful toggle into an error response.
  if (parsed.data.isOnline) {
    try {
      await matchPendingTrips();
    } catch (err) {
      console.error("Failed to retry matching pending trips", err);
    }
  }
  res.json(updated);
});

const locationPingSchema = z.object({
  lat: z.number().finite().gte(-90).lte(90),
  lng: z.number().finite().gte(-180).lte(180),
});

// Driver: report my current position while online. This is what backs the
// admin Live Map (GET /admin/live-map) for drivers who aren't mid-trip — the
// existing WebSocket location feed (realtime/hub.ts) only fires once a rider
// has an active trip room to broadcast into, so an idle "available" driver
// still needs a way to be seen on the map. Same in-memory hub either way —
// this is a plain REST fallback, not a second source of truth.
driversRouter.post("/drivers/me/location", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = locationPingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const location = recordDriverLocation(driver.id, parsed.data.lat, parsed.data.lng);
  res.json(location);
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

// Admin: a short-lived signed URL to view one of this driver's uploaded
// onboarding documents. The document's fileKey is never returned to the
// client as a usable URL (documents.routes.ts / GET /drivers/:id return the
// raw key, which only identifies the private S3 object) — a fresh signed URL
// is generated here on demand, each time the admin actually wants to look at
// it, and is never persisted (matches the proof-of-delivery pattern in
// courier.routes.ts's withProofUrls, just as an on-demand endpoint instead of
// eagerly signing every document on every driver-detail fetch).
driversRouter.get(
  "/drivers/:driverId/documents/:documentId/url",
  requireAuth,
  requireAdminPermission("drivers:write"),
  async (req, res) => {
    const driver = await prisma.driver.findUnique({ where: { id: req.params.driverId } });
    if (!driver) return res.status(404).json({ error: "Driver could not be found." });

    const doc = await prisma.driverDocument.findUnique({ where: { id: req.params.documentId } });
    // Same 404 whether the document doesn't exist at all or belongs to a
    // different driver — this endpoint should never confirm or deny that a
    // given document ID exists for a driver the caller didn't ask about.
    if (!doc || doc.driverId !== driver.id) {
      return res.status(404).json({ error: "Document could not be found." });
    }
    if (!doc.fileKey) {
      return res.status(404).json({ error: "The document record exists, but no file has been uploaded for it." });
    }
    if (!env.DOCUMENTS_BUCKET) {
      return res.status(503).json({ error: "Document storage is not configured." });
    }

    let url: string;
    try {
      url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: env.DOCUMENTS_BUCKET, Key: doc.fileKey }), {
        expiresIn: DOCUMENT_URL_EXPIRY_SECONDS,
      });
    } catch (err) {
      console.error("Failed to sign driver document URL", err);
      return res.status(502).json({ error: "Unable to open this document right now. Please try again." });
    }

    // Awaited for the same reason as the other admin-audit writes in this
    // codebase: recordAudit never throws, so this can't turn a real failure
    // into one, and it guarantees the audit row exists before the response.
    await recordAudit({
      actorSub: req.user!.sub,
      action: "DOCUMENT_VIEWED",
      entityType: "DriverDocument",
      entityId: doc.id,
      metadata: { driverId: driver.id },
    });

    res.json({ url, expiresIn: DOCUMENT_URL_EXPIRY_SECONDS });
  },
);

const statusSchema = z.object({
  status: z.enum(DRIVER_STATUSES),
});

const DRIVER_STATUS_MESSAGES: Record<"ACTIVE" | "PENDING_REVIEW" | "SUSPENDED", { title: string; body: string }> = {
  ACTIVE: {
    title: "You're approved!",
    body: "Your driver account has been approved. You can now go online and start accepting trips.",
  },
  SUSPENDED: {
    title: "Account suspended",
    body: "Your driver account has been suspended. Contact support for details.",
  },
  PENDING_REVIEW: {
    title: "Application under review",
    body: "Your driver account is back under review. We'll notify you once it's decided.",
  },
};

// Admin: approve (ACTIVE) / suspend / send back to review. This is THE
// approval endpoint — Driver.status is the single authoritative approval
// field the driver app (GET /drivers/me), the go-online gate
// (PATCH /drivers/me/availability) and trip matching (services/matching.ts)
// all read. Reviewing individual documents (PATCH /documents/:id/review)
// records the outcome per document but never changes this field; an admin
// must explicitly approve the driver here.
driversRouter.patch("/drivers/:id/status", requireAuth, requireAdminPermission("drivers:write"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.driver.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Driver could not be found." });

  // Idempotent: a repeated/duplicate approval (double-tap, retry after a
  // timeout, stale admin screen) must not re-notify the driver "You're
  // approved!" or write a second audit row for a change that never happened.
  // 200 with the current record so the caller still converges on the truth.
  if (existing.status === parsed.data.status) return res.json(existing);

  const driver = await prisma.driver.update({
    where: { id: existing.id },
    data: { status: parsed.data.status },
  });
  // Awaited (like the other admin-audit writes in this codebase) so the
  // audit row is guaranteed to exist before the admin sees a 200; recordAudit
  // never throws, so this can't turn a successful approval into an error.
  await recordAudit({
    actorSub: req.user!.sub,
    action: "DRIVER_STATUS_CHANGED",
    entityType: "Driver",
    entityId: driver.id,
    metadata: { from: existing.status, status: parsed.data.status },
  });
  // EI-1 gap closed: an approval/suspension/rejection previously only wrote
  // an audit row — the driver themself was never told their account status
  // had changed at all. Best-effort (persisted in-app row + device push);
  // the database status above is the source of truth, this is only how the
  // driver app learns to re-fetch it.
  const message = DRIVER_STATUS_MESSAGES[parsed.data.status];
  await notifyUser(driver.userId, "DRIVER_ACCOUNT_STATUS_CHANGED", message.title, message.body);
  res.json(driver);
});

// Driver: toggle online preference is handled client-side / via a lightweight presence
// table in a later iteration; ride matching (websocket/App Sync) is intentionally out
// of scope for this MVP skeleton.
