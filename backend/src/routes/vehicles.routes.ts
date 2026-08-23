import { Router, type Request, type Response } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { findOwnDriver } from "../services/driver";
import { resolveAssetUrl } from "../services/assets";

export const vehiclesRouter = Router();

// Driver: list my own vehicles
vehiclesRouter.get("/vehicles/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicles = await prisma.vehicle.findMany({ where: { driverId: driver.id } });
  res.json(vehicles);
});

const baseVehicleSchema = z.object({
  brand: z.string().min(1),
  model: z.string().min(1),
  colour: z.string().min(1),
  plateNumber: z.string().min(1),
  year: z.string().min(4),
  isPrimary: z.boolean().default(false),
});

// imageKey: the S3 object key returned by POST /uploads/presign (bucket:
// "assets"), never a raw URL — validated below to belong to the calling
// user before it's resolved and stored, the same ownership pattern
// documents.routes.ts already uses for DriverDocument.fileKey.
const createVehicleSchema = baseVehicleSchema.extend({
  imageKey: z.string().min(1).optional(),
});

/** Rejects an imageKey that wasn't actually issued to the calling user by
 * POST /uploads/presign — every key that endpoint mints is namespaced
 * `${callerSub}/...`, so anything else was never handed to this caller.
 * Without this check, a driver who knew (or guessed) another user's sub and
 * object key could attach that file to their own vehicle. Returns a resolved
 * imageUrl on success, or sends the 403 itself and returns undefined. */
function resolveOwnedImageUrl(req: Request, res: Response, imageKey: string | undefined) {
  if (imageKey === undefined) return { ok: true as const, imageUrl: undefined };
  if (!imageKey.startsWith(`${req.user!.sub}/`)) {
    res.status(403).json({ error: "imageKey must belong to the calling user" });
    return { ok: false as const };
  }
  return { ok: true as const, imageUrl: resolveAssetUrl(imageKey) };
}

// Driver: add a vehicle
vehiclesRouter.post("/vehicles", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { imageKey, ...vehicleFields } = parsed.data;
  const imageResolution = resolveOwnedImageUrl(req, res, imageKey);
  if (!imageResolution.ok) return;

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.$transaction(async (tx) => {
    // "Primary vehicle" is meant to be exclusive per driver (matching.ts
    // picks a vehicle by `orderBy: { isPrimary: "desc" }`, which only means
    // anything if at most one vehicle can be primary at a time) — unset any
    // existing primary on this driver's other vehicles in the same
    // transaction as setting this one, so it's never possible to end up
    // with two.
    if (vehicleFields.isPrimary) {
      await tx.vehicle.updateMany({
        where: { driverId: driver.id, isPrimary: true },
        data: { isPrimary: false },
      });
    }
    return tx.vehicle.create({
      data: { ...vehicleFields, imageUrl: imageResolution.imageUrl, driverId: driver.id },
    });
  });
  res.status(201).json(vehicle);
});

const updateVehicleSchema = createVehicleSchema.partial();

// Driver: update one of my own vehicles
vehiclesRouter.patch("/vehicles/:id", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { imageKey, ...vehicleFields } = parsed.data;
  const imageResolution = resolveOwnedImageUrl(req, res, imageKey);
  if (!imageResolution.ok) return;

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const updated = await prisma.$transaction(async (tx) => {
    // Same exclusivity as POST /vehicles above — setting this vehicle
    // primary unsets it on every other vehicle this driver owns.
    if (vehicleFields.isPrimary) {
      await tx.vehicle.updateMany({
        where: { driverId: driver.id, isPrimary: true, id: { not: req.params.id } },
        data: { isPrimary: false },
      });
    }
    return tx.vehicle.update({
      where: { id: req.params.id },
      data: { ...vehicleFields, ...(imageResolution.imageUrl !== undefined ? { imageUrl: imageResolution.imageUrl } : {}) },
    });
  });
  res.json(updated);
});
