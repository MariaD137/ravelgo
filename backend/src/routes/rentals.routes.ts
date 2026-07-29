import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const rentalsRouter = Router();

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

const createRentalSchema = z.object({
  vehicleId: z.string().min(1),
  dailyRate: z.number().positive(),
  location: z.string().min(1),
});

// Driver: list a vehicle for luxury rental
rentalsRouter.post("/rentals", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createRentalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicle = await prisma.vehicle.findUnique({ where: { id: parsed.data.vehicleId } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const listing = await prisma.rentalListing.create({
    data: { ...parsed.data, driverId: driver.id },
  });
  await prisma.vehicle.update({ where: { id: vehicle.id }, data: { listedForRental: true } });

  res.status(201).json(listing);
});

// Driver: view my own rental listings
rentalsRouter.get("/rentals/mine", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const listings = await prisma.rentalListing.findMany({
    where: { driverId: driver.id },
    include: { vehicle: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(listings);
});

// Riders/public: browse approved rental listings
rentalsRouter.get("/rentals", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const groups = req.user!.groups;
  const isAdmin = groups.includes("Admin");
  const where = isAdmin ? {} : { status: "APPROVED" as const };

  const [listings, total] = await Promise.all([
    prisma.rentalListing.findMany({
      where,
      include: { vehicle: true, driver: { include: { user: true } } },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.rentalListing.count({ where }),
  ]);
  res.json(paginate(listings, total, page, pageSize));
});

const decisionSchema = z.object({ status: z.enum(["APPROVED", "REJECTED"]) });

// Admin: approve/reject a rental listing
rentalsRouter.patch("/rentals/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const listing = await prisma.rentalListing.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  res.json(listing);
});
