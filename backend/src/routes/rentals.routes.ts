import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { findOwnDriver } from "../services/driver";
import { DriverBusyConflict, sendDriverBusyResponse } from "../services/driver-availability";
import {
  RentalBookingStateError,
  RentalOverlapConflict,
  activateBooking,
  createBooking,
  decideBooking,
  endBooking,
} from "../services/rentals";

export const rentalsRouter = Router();

/** Loads a RentalBooking along with the driverId of its listing's owner, or
 * null if it doesn't exist — shared by every booking-lifecycle route below
 * that needs to check "is the caller the listing's own driver." */
async function findBookingWithOwner(bookingId: string) {
  return prisma.rentalBooking.findUnique({
    where: { id: bookingId },
    include: { rentalListing: true },
  });
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

const createBookingSchema = z.object({
  startAt: z.coerce.date(),
  endAt: z.coerce.date(),
});

// Any authenticated user: book an APPROVED rental listing for a date range.
// A real transaction against the listing (the ad) — see services/rentals.ts
// for the overlap-prevention and price-computation rules.
rentalsRouter.post("/rentals/:id/bookings", requireAuth, async (req, res) => {
  const parsed = createBookingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const renter = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!renter) return res.status(404).json({ error: "User not found" });

  try {
    const booking = await createBooking({
      rentalListingId: req.params.id,
      renterId: renter.id,
      startAt: parsed.data.startAt,
      endAt: parsed.data.endAt,
    });
    res.status(201).json(booking);
  } catch (err) {
    if (err instanceof RentalOverlapConflict) {
      return res.status(409).json({ code: "RENTAL_OVERLAP", message: err.message });
    }
    if (err instanceof RentalBookingStateError) {
      return res.status(err.message === "Rental listing not found" ? 404 : 409).json({ error: err.message });
    }
    throw err;
  }
});

// Renter: view my own bookings
rentalsRouter.get("/rentals/bookings/mine", requireAuth, async (req, res) => {
  const renter = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!renter) return res.status(404).json({ error: "User not found" });

  const bookings = await prisma.rentalBooking.findMany({
    where: { renterId: renter.id },
    include: { rentalListing: { include: { vehicle: true } } },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings);
});

// Driver (listing owner) or Admin: view bookings for one of my listings
rentalsRouter.get("/rentals/:id/bookings", requireAuth, async (req, res) => {
  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await findOwnDriver(req.user!.sub);
    const listing = driver && (await prisma.rentalListing.findUnique({ where: { id: req.params.id } }));
    if (!driver || !listing || listing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to view these bookings" });
    }
  }

  const bookings = await prisma.rentalBooking.findMany({
    where: { rentalListingId: req.params.id },
    include: { renter: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings);
});

const bookingDecisionSchema = z.object({ status: z.enum(["CONFIRMED", "REJECTED"]) });

// Driver (listing owner): confirm or reject a REQUESTED booking
rentalsRouter.patch("/rentals/bookings/:id/decision", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = bookingDecisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  const booking = await findBookingWithOwner(req.params.id);
  if (!driver || !booking || booking.rentalListing.driverId !== driver.id) {
    return res.status(404).json({ error: "Booking not found" });
  }

  try {
    res.json(await decideBooking(req.params.id, parsed.data.status));
  } catch (err) {
    if (err instanceof RentalBookingStateError) return res.status(409).json({ error: err.message });
    throw err;
  }
});

// Driver (listing owner): mark a CONFIRMED booking ACTIVE (handover done).
// This is the transition that actually reserves the driver — see
// activateBooking's own doc comment.
rentalsRouter.patch("/rentals/bookings/:id/activate", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  const booking = await findBookingWithOwner(req.params.id);
  if (!driver || !booking || booking.rentalListing.driverId !== driver.id) {
    return res.status(404).json({ error: "Booking not found" });
  }

  try {
    res.json(await activateBooking(req.params.id, driver.id));
  } catch (err) {
    if (err instanceof RentalBookingStateError) return res.status(409).json({ error: err.message });
    if (err instanceof DriverBusyConflict) return sendDriverBusyResponse(res, err);
    throw err;
  }
});

const endBookingSchema = z.object({ status: z.enum(["COMPLETED", "CANCELLED"]) });

// Driver (listing owner): mark a booking COMPLETED (vehicle returned) or
// CANCELLED, releasing the driver's active RENTAL assignment if one exists.
rentalsRouter.patch("/rentals/bookings/:id/end", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = endBookingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  const booking = await findBookingWithOwner(req.params.id);
  if (!driver || !booking || booking.rentalListing.driverId !== driver.id) {
    return res.status(404).json({ error: "Booking not found" });
  }

  res.json(await endBooking(req.params.id, parsed.data.status, driver.id));
});

// Renter: cancel my own booking before it becomes ACTIVE
rentalsRouter.patch("/rentals/bookings/:id/cancel", requireAuth, async (req, res) => {
  const renter = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  const booking = await prisma.rentalBooking.findUnique({ where: { id: req.params.id } });
  if (!renter || !booking || booking.renterId !== renter.id) {
    return res.status(404).json({ error: "Booking not found" });
  }
  if (booking.status !== "REQUESTED" && booking.status !== "CONFIRMED") {
    return res.status(409).json({ error: `Booking cannot be cancelled from status ${booking.status}` });
  }

  const cancelled = await prisma.rentalBooking.update({
    where: { id: req.params.id },
    data: { status: "CANCELLED" },
  });
  res.json(cancelled);
});
