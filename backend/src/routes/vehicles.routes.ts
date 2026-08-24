import { Router } from "express";
import { z } from "zod";
import type { DriverDocument, Vehicle, VehiclePhoto } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { Errors } from "../lib/errors";
import { assertFileKeyOwnedByUser } from "../lib/fileKey";
import { publicAssetUrl } from "../lib/assetUrl";
import { asyncHandler } from "../middleware/async-handler";

export const vehiclesRouter = Router();

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

async function findSelfUser(cognitoSub: string) {
  return prisma.user.findUnique({ where: { cognitoSub } });
}

const vehicleInclude = {
  photos: { orderBy: { displayOrder: "asc" as const } },
  documents: true,
};

type VehicleWithOptionalRelations = Vehicle & {
  photos?: VehiclePhoto[];
  documents?: DriverDocument[];
};

// Vehicle photos live in the CloudFront-fronted public assets bucket (see
// infra/lib/storage-stack.ts) — no presigning needed to view them, unlike
// documents. `url` is null (not a broken link) if ASSETS_CLOUDFRONT_DOMAIN
// isn't configured for this environment.
function serializeVehicle(vehicle: VehicleWithOptionalRelations) {
  const photos = vehicle.photos ?? [];
  const documents = vehicle.documents ?? [];
  return {
    ...vehicle,
    photos: photos.map((p) => ({ ...p, url: publicAssetUrl(p.fileKey) })),
    documents,
  };
}

// Driver: list my own vehicles (active and deactivated alike — nothing
// disappears silently; the client decides how to present isActive).
vehiclesRouter.get("/vehicles/me", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicles = await prisma.vehicle.findMany({
    where: { driverId: driver.id },
    include: vehicleInclude,
    orderBy: { createdAt: "desc" },
  });
  res.json(vehicles.map(serializeVehicle));
}));

// Driver: get one of my own vehicles, with photos and documents.
// Registered after "/vehicles/me" — see the same ordering note on
// GET /drivers/:id in drivers.routes.ts (":id" would otherwise swallow
// "me" if registered first).
vehiclesRouter.get("/vehicles/:id", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findFirst({
    where: { id: req.params.id, driverId: driver.id },
    include: vehicleInclude,
  });
  if (!vehicle) return res.status(404).json({ error: "Vehicle not found" });
  res.json(serializeVehicle(vehicle));
}));

const vehicleTypeEnum = z.enum(["SEDAN", "SUV", "VAN", "TRUCK", "MOTORCYCLE", "LUXURY", "OTHER"]);

const createVehicleSchema = z.object({
  brand: z.string().min(1),
  model: z.string().min(1),
  colour: z.string().min(1),
  plateNumber: z.string().min(1),
  year: z.string().min(4),
  vin: z.string().min(5).max(32).optional(),
  vehicleType: vehicleTypeEnum.optional(),
  isPrimary: z.boolean().default(false),
});

// Driver: add a vehicle. Every new vehicle starts PENDING verification (the
// Vehicle model's default) — creating it *is* the submission; there's no
// separate draft state.
vehiclesRouter.post("/vehicles", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = createVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.create({
    data: { ...parsed.data, driverId: driver.id },
  });
  res.status(201).json(serializeVehicle(vehicle));
}));

const updateVehicleSchema = createVehicleSchema.partial();

// Driver: update one of my own vehicles
vehiclesRouter.patch("/vehicles/:id", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = updateVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const updated = await prisma.vehicle.update({
    where: { id: req.params.id },
    data: parsed.data,
  });
  res.json(serializeVehicle(updated));
}));

// Driver: safely deactivate my own vehicle. A soft flag, never a hard
// delete — verification history and anything referencing this vehicle
// (rental listings, documents) must survive. There is deliberately no
// reactivate endpoint yet (out of scope for this pass); the vehicle stays
// visible with isActive:false rather than disappearing.
vehiclesRouter.patch("/vehicles/:id/deactivate", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver) throw Errors.notFound("Driver profile");

    const vehicle = await prisma.vehicle.findFirst({ where: { id: req.params.id, driverId: driver.id } });
    if (!vehicle) throw Errors.notFound("Vehicle");

    const updated = await prisma.vehicle.update({ where: { id: vehicle.id }, data: { isActive: false } });
    res.json(serializeVehicle(updated));
  } catch (err) {
    next(err);
  }
});

// Driver: resubmit a rejected vehicle for re-review. Only valid from
// REJECTED/RESUBMISSION_REQUIRED — resets to PENDING and clears the prior
// rejection reason so the driver's next view reflects the new review cycle,
// not stale feedback.
vehiclesRouter.post("/vehicles/:id/resubmit", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver) throw Errors.notFound("Driver profile");

    const vehicle = await prisma.vehicle.findFirst({ where: { id: req.params.id, driverId: driver.id } });
    if (!vehicle) throw Errors.notFound("Vehicle");

    if (vehicle.verificationStatus !== "REJECTED" && vehicle.verificationStatus !== "RESUBMISSION_REQUIRED") {
      throw Errors.conflict("Only a rejected vehicle can be resubmitted.");
    }

    const updated = await prisma.vehicle.update({
      where: { id: vehicle.id },
      data: { verificationStatus: "PENDING", verificationReason: null },
    });
    res.json(serializeVehicle(updated));
  } catch (err) {
    next(err);
  }
});

const addPhotoSchema = z.object({
  fileKey: z.string().min(1),
  photoType: z.enum(["FRONT", "REAR", "LEFT_SIDE", "RIGHT_SIDE", "INTERIOR", "OTHER"]).default("OTHER"),
  displayOrder: z.number().int().min(0).default(0),
});

// Driver: attach a photo to one of my own vehicles, after uploading the
// bytes to S3 via POST /uploads/presign. fileKey ownership is verified
// server-side — a driver cannot register a fileKey that wasn't issued to
// them (see assertFileKeyOwnedByUser).
vehiclesRouter.post("/vehicles/:id/photos", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const parsed = addPhotoSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const driver = await findOwnDriver(req.user!.sub);
    if (!driver) throw Errors.notFound("Driver profile");

    const vehicle = await prisma.vehicle.findFirst({ where: { id: req.params.id, driverId: driver.id } });
    if (!vehicle) throw Errors.notFound("Vehicle");

    assertFileKeyOwnedByUser(parsed.data.fileKey, req.user!.sub);

    const photo = await prisma.vehiclePhoto.create({
      data: {
        vehicleId: vehicle.id,
        fileKey: parsed.data.fileKey,
        photoType: parsed.data.photoType,
        displayOrder: parsed.data.displayOrder,
      },
    });
    res.status(201).json({ ...photo, url: publicAssetUrl(photo.fileKey) });
  } catch (err) {
    next(err);
  }
});

// Driver: remove a photo from one of my own vehicles. Deletes the metadata
// row only — the underlying S3 object is left for bucket lifecycle rules to
// reap, matching the pattern already established for driver documents
// (fileKey rows are never scrubbed from S3 by the API layer today).
vehiclesRouter.delete("/vehicles/:id/photos/:photoId", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver) throw Errors.notFound("Driver profile");

    const vehicle = await prisma.vehicle.findFirst({ where: { id: req.params.id, driverId: driver.id } });
    if (!vehicle) throw Errors.notFound("Vehicle");

    const photo = await prisma.vehiclePhoto.findFirst({ where: { id: req.params.photoId, vehicleId: vehicle.id } });
    if (!photo) throw Errors.notFound("Photo");

    await prisma.vehiclePhoto.delete({ where: { id: photo.id } });
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

const vehicleReviewSchema = z.object({
  status: z.enum(["APPROVED", "REJECTED"]),
  reason: z.string().min(1).optional(),
});

// Admin: approve or reject a vehicle. A reason is mandatory when rejecting
// — there is no way to submit a REJECTED review without one, matching the
// same rule as document review below.
vehiclesRouter.patch("/vehicles/:id/review", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const parsed = vehicleReviewSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
    if (parsed.data.status === "REJECTED" && !parsed.data.reason) {
      return res.status(400).json({ error: "A rejection reason is required." });
    }

    const adminUser = await findSelfUser(req.user!.sub);
    if (!adminUser) throw Errors.notFound("Admin user");

    const vehicle = await prisma.vehicle.update({
      where: { id: req.params.id },
      data: {
        verificationStatus: parsed.data.status,
        verificationReason: parsed.data.status === "REJECTED" ? parsed.data.reason : null,
        verifiedAt: new Date(),
        verifiedById: adminUser.id,
      },
    });
    res.json(serializeVehicle(vehicle));
  } catch (err) {
    next(err);
  }
});
