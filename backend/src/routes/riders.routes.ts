import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { validate } from "../lib/validate";
import { Errors } from "../lib/errors";

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

// Rider: update my own profile (name/phone — not email, which is tied to
// the Cognito identity this row was bootstrapped from). Uses the same
// conditional-updateMany pattern as the state-machine routes: a plain
// prisma.user.update() would throw P2025 (record not found) for a rider
// who never called POST /riders/me first, so the "did this hit a row"
// check and the write happen in one statement instead.
const updateMeSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  phoneNumber: z.string().optional(),
});

ridersRouter.patch("/riders/me", requireAuth, requireRole("Rider"), async (req, res, next) => {
  try {
    const data = validate<typeof updateMeSchema._output>(updateMeSchema, req.body, "Request body");
    const { count } = await prisma.user.updateMany({ where: { cognitoSub: req.user!.sub }, data });
    if (count === 0) throw Errors.notFound("Rider profile");
    const rider = await prisma.user.findUniqueOrThrow({ where: { cognitoSub: req.user!.sub } });
    res.json(rider);
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
ridersRouter.patch("/riders/:id/status", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const data = validate<{ suspended: boolean }>(statusSchema, req.body, "Request body");

    const rider = await prisma.user.update({
      where: { id: req.params.id },
      data: { suspended: data.suspended },
    });
    res.json(rider);
  } catch (err) {
    next(err);
  }
});
