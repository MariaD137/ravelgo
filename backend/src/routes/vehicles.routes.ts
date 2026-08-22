import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { findOwnDriver } from "../services/driver";

export const vehiclesRouter = Router();

// Driver: list my own vehicles
vehiclesRouter.get("/vehicles/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicles = await prisma.vehicle.findMany({ where: { driverId: driver.id } });
  res.json(vehicles);
});

const createVehicleSchema = z.object({
  brand: z.string().min(1),
  model: z.string().min(1),
  colour: z.string().min(1),
  plateNumber: z.string().min(1),
  year: z.string().min(4),
  isPrimary: z.boolean().default(false),
});

// Driver: add a vehicle
vehiclesRouter.post("/vehicles", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.$transaction(async (tx) => {
    // "Primary vehicle" is meant to be exclusive per driver (matching.ts
    // picks a vehicle by `orderBy: { isPrimary: "desc" }`, which only means
    // anything if at most one vehicle can be primary at a time) — unset any
    // existing primary on this driver's other vehicles in the same
    // transaction as setting this one, so it's never possible to end up
    // with two.
    if (parsed.data.isPrimary) {
      await tx.vehicle.updateMany({
        where: { driverId: driver.id, isPrimary: true },
        data: { isPrimary: false },
      });
    }
    return tx.vehicle.create({ data: { ...parsed.data, driverId: driver.id } });
  });
  res.status(201).json(vehicle);
});

const updateVehicleSchema = createVehicleSchema.partial();

// Driver: update one of my own vehicles
vehiclesRouter.patch("/vehicles/:id", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const updated = await prisma.$transaction(async (tx) => {
    // Same exclusivity as POST /vehicles above — setting this vehicle
    // primary unsets it on every other vehicle this driver owns.
    if (parsed.data.isPrimary) {
      await tx.vehicle.updateMany({
        where: { driverId: driver.id, isPrimary: true, id: { not: req.params.id } },
        data: { isPrimary: false },
      });
    }
    return tx.vehicle.update({ where: { id: req.params.id }, data: parsed.data });
  });
  res.json(updated);
});
