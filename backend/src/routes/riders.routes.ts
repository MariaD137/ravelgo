import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { validate } from "../lib/validate";
import { Errors } from "../lib/errors";
import { recordAudit } from "../lib/audit";
import { cognitoGroups } from "../services/cognito";

export const ridersRouter = Router();

// Admin: list all riders
ridersRouter.get("/riders", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const { page, pageSize } = validate<{ page: number; pageSize: number }>(
      paginationQuerySchema,
      req.query,
      "Query parameters",
    );

    const [riders, total] = await Promise.all([
      prisma.user.findMany({
        where: { role: "RIDER" },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      prisma.user.count({ where: { role: "RIDER" } }),
    ]);
    res.json(paginate(riders, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});

// Rider: get my own profile (creates it on first call, since Cognito sign-up
// doesn't itself create a Postgres row — the app calls this right after auth)
const meSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phoneNumber: z.string().optional(),
});

ridersRouter.post("/riders/me", requireAuth, requireRole("Rider"), async (req, res, next) => {
  try {
    const data = validate<typeof meSchema._output>(meSchema, req.body, "Request body");

    const rider = await prisma.user.upsert({
      where: { cognitoSub: req.user!.sub },
      update: {},
      create: { cognitoSub: req.user!.sub, role: "RIDER", ...data },
    });
    res.status(201).json(rider);
  } catch (err) {
    next(err);
  }
});

ridersRouter.get("/riders/me", requireAuth, requireRole("Rider"), async (req, res, next) => {
  try {
    const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
    if (!rider) throw Errors.notFound("Rider profile");
    res.json(rider);
  } catch (err) {
    next(err);
  }
});

// Rider: update my own profile. Email is intentionally excluded — it's tied
// to the Cognito identity used to sign in, not editable from here.
const updateMeSchema = z
  .object({
    firstName: z.string().min(1),
    lastName: z.string().min(1),
    phoneNumber: z.string().min(1),
  })
  .partial()
  .refine((data) => Object.keys(data).length > 0, "At least one field is required");

ridersRouter.patch("/riders/me", requireAuth, requireRole("Rider"), async (req, res, next) => {
  try {
    const data = validate<typeof updateMeSchema._output>(updateMeSchema, req.body, "Request body");

    const existing = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
    if (!existing) throw Errors.notFound("Rider profile");

    const rider = await prisma.user.update({ where: { id: existing.id }, data });
    res.json(rider);
  } catch (err) {
    next(err);
  }
});

// Rider: permanently delete my own account (self-service, required by app
// stores / privacy law). Soft-delete — stamp deletedAt, which the User model
// is explicitly designed for so the ledger and every financial FK survive
// (see schema.prisma) — then disable the Cognito account and revoke its
// refresh tokens, the same enforcement model as admin suspension: no new
// token can be minted, and any access token already issued expires within its
// ~1h TTL. Reversible by support if ever needed (clear deletedAt + re-enable
// in Cognito). Only ever touches the caller's own row, keyed by the verified
// sub — never a client-supplied id.
ridersRouter.delete("/riders/me", requireAuth, requireRole("Rider"), async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
    if (!user) throw Errors.notFound("Rider profile");

    if (!user.deletedAt) {
      await prisma.user.update({ where: { id: user.id }, data: { deletedAt: new Date() } });
    }
    // Best-effort account lockout; a failure here shouldn't leave the caller
    // thinking deletion failed when the row is already soft-deleted.
    await cognitoGroups.setUserEnabled(req.user!.sub, false);
    await cognitoGroups.globalSignOut(req.user!.sub);

    void recordAudit({
      actorSub: req.user!.sub,
      action: "RIDER_ACCOUNT_DELETED",
      entityType: "User",
      entityId: user.id,
      metadata: {},
    });
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

// Admin: get a single rider with trip history.
// Registered after the literal "/riders/me" routes above — Express matches
// path segments in registration order, so ":id" would otherwise swallow
// "me" and shadow the rider's own-profile routes with this Admin check.
ridersRouter.get("/riders/:id", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const rider = await prisma.user.findFirst({
      where: { id: req.params.id, role: "RIDER" },
      include: { ridesAsRider: { orderBy: { requestedAt: "desc" }, take: 20 } },
    });
    if (!rider) throw Errors.notFound("Rider");
    res.json(rider);
  } catch (err) {
    next(err);
  }
});

const statusSchema = z.object({ suspended: z.boolean() });

// Admin: suspend / reactivate a rider
ridersRouter.patch("/riders/:id/status", requireAuth, requireAdminPermission("riders:write"), async (req, res, next) => {
  try {
    const data = validate<{ suspended: boolean }>(statusSchema, req.body, "Request body");

    const rider = await prisma.user.update({
      where: { id: req.params.id },
      data: { suspended: data.suspended },
    });
    void recordAudit({
      actorSub: req.user!.sub,
      action: data.suspended ? "RIDER_SUSPENDED" : "RIDER_REINSTATED",
      entityType: "User",
      entityId: rider.id,
    });
    res.json(rider);
  } catch (err) {
    next(err);
  }
});
