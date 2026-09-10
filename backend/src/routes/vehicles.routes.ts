import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { photoUrlFor, serializeVehicle } from "../lib/vehicle-view";

export const vehiclesRouter = Router();

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

// Admin: inventory of every vehicle across all drivers, with owner info and
// whether it's currently listed for rental. Registered before "/vehicles/me"
// would matter only if it were also literal "/vehicles" - Express matches
// the two paths independently either way.
vehiclesRouter.get("/vehicles", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [vehicles, total] = await Promise.all([
    prisma.vehicle.findMany({
      include: {
        driver: { include: { user: { select: { firstName: true, lastName: true, email: true } } } },
        _count: { select: { rentalListings: true } },
      },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.vehicle.count(),
  ]);
  // Admin-only view: keeps the raw driver.user include (email is genuinely
  // useful here) but still runs photoKeys through the same URL builder as
  // everywhere else rather than leaking the raw S3 keys.
  res.json(
    paginate(
      vehicles.map((v) => {
        const { photoUrl, photoUrls } = serializeVehicle(v);
        return { ...v, photoKeys: undefined, photoUrl, photoUrls };
      }),
      total,
      page,
      pageSize,
    ),
  );
});

const setVehicleClassSchema = z.object({
  vehicleClass: z.enum(["ECONOMY", "COMFORT", "PREMIUM", "LUXURY"]).nullable(),
});

// Admin: correct/set any vehicle's ride-category eligibility class (pricing
// spec #22/#23 — "Admin must control which vehicles qualify for each ride
// category"), independent of the driver's own self-declared value.
vehiclesRouter.patch("/admin/vehicles/:id/class", requireAuth, requireAdminPermission("drivers:write"), async (req, res) => {
  const parsed = setVehicleClassSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
  if (!vehicle) return res.status(404).json({ error: "Vehicle not found" });

  const updated = await prisma.vehicle.update({
    where: { id: req.params.id },
    data: { vehicleClass: parsed.data.vehicleClass },
  });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "VEHICLE_CLASS_SET",
    entityType: "Vehicle",
    entityId: vehicle.id,
    metadata: { from: vehicle.vehicleClass, to: parsed.data.vehicleClass },
  });
  res.json(serializeVehicle(updated));
});

// Driver: list my own vehicles
vehiclesRouter.get("/vehicles/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicles = await prisma.vehicle.findMany({ where: { driverId: driver.id } });
  res.json(vehicles.map(serializeVehicle));
});

// S3 keys uploaded via POST /uploads/presign always carry the caller's own
// Cognito sub as a prefix — this rejects one caller submitting a key that
// was actually presigned for (and uploaded by) someone else. Same pattern
// courier.routes.ts uses for proof-of-delivery keys.
function ownsUploadKey(sub: string, key: string): boolean {
  return key.startsWith(`${sub}/`);
}

const createVehicleSchema = z.object({
  brand: z.string().min(1),
  model: z.string().min(1),
  colour: z.string().min(1),
  plateNumber: z.string().min(1),
  year: z.string().min(4),
  isPrimary: z.boolean().default(false),
  // Which ride categories this vehicle is eligible for (RideCategory.
  // eligibleVehicleClasses) — self-declared by the driver, admin-correctable.
  // Optional — a vehicle can be added first and classified later via PATCH.
  vehicleClass: z.enum(["ECONOMY", "COMFORT", "PREMIUM", "LUXURY"]).optional(),
  // S3 keys from POST /uploads/presign (bucket: "assets"), up to 7 per
  // vehicle. Optional — a vehicle can be added first and photographed later
  // via PATCH.
  photoKeys: z.array(z.string().min(1)).max(7).optional(),
});

// Driver: add a vehicle
vehiclesRouter.post("/vehicles", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  if (parsed.data.photoKeys?.some((key) => !ownsUploadKey(req.user!.sub, key))) {
    return res.status(403).json({ error: "Uploaded file does not belong to the calling user" });
  }

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.create({
    data: { ...parsed.data, driverId: driver.id },
  });
  res.status(201).json(serializeVehicle(vehicle));
});

// Photo edits use add/remove rather than a full replace: the client is
// never handed the raw S3 keys (only photoUrl/photoUrls), so it can't
// resubmit "the full desired list" the way it can for a plain text field —
// it can only say which newly-presigned keys to append and which existing
// photoUrl values (as returned by GET) to drop.
const updateVehicleSchema = createVehicleSchema
  .omit({ photoKeys: true })
  .partial()
  .extend({
    addPhotoKeys: z.array(z.string().min(1)).max(7).optional(),
    removePhotoUrls: z.array(z.string().min(1)).max(7).optional(),
  });

// Driver: update one of my own vehicles
vehiclesRouter.patch("/vehicles/:id", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = updateVehicleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  if (parsed.data.addPhotoKeys?.some((key) => !ownsUploadKey(req.user!.sub, key))) {
    return res.status(403).json({ error: "Uploaded file does not belong to the calling user" });
  }

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.id } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const { addPhotoKeys, removePhotoUrls, ...rest } = parsed.data;
  let photoKeys = vehicle.photoKeys;
  if (removePhotoUrls?.length) {
    const removeSet = new Set(removePhotoUrls);
    photoKeys = photoKeys.filter((key) => !removeSet.has(photoUrlFor(key) ?? ""));
  }
  if (addPhotoKeys?.length) {
    photoKeys = [...photoKeys, ...addPhotoKeys];
  }
  if (photoKeys.length > 7) {
    return res.status(400).json({ error: "A vehicle can have at most 7 photos." });
  }

  const updated = await prisma.vehicle.update({
    where: { id: req.params.id },
    data: { ...rest, photoKeys },
  });
  res.json(serializeVehicle(updated));
});

// Driver: delete one of my own vehicles. Blocked while it's listed for
// rental — a RentalBooking is RESTRICTed against RentalListing, so deleting
// the vehicle out from under an active listing would otherwise fail at the
// DB layer with a raw 500 instead of a clear, actionable error.
vehiclesRouter.delete("/vehicles/:id", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({
    where: { id: req.params.id },
    include: { rentalListings: true },
  });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }
  if (vehicle.rentalListings.length > 0) {
    return res.status(409).json({ error: "This vehicle is listed for rental. Remove the rental listing before deleting it." });
  }

  await prisma.vehicle.delete({ where: { id: vehicle.id } });
  res.status(204).send();
});
