import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { InsufficientFundsError } from "../services/wallet";
import { RentalBookingNotChargeableError, cancelRentalBooking, chargeRentalBooking } from "../services/rental-payment";

export const rentalsRouter = Router();

const MS_PER_DAY = 24 * 60 * 60 * 1000;

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

async function findOwnUser(cognitoSub: string) {
  return prisma.user.findUnique({ where: { cognitoSub } });
}

function respondToChargeError(res: import("express").Response, err: unknown, next: import("express").NextFunction) {
  if (err instanceof InsufficientFundsError) return res.status(402).json({ error: "Insufficient wallet balance" });
  if (err instanceof RentalBookingNotChargeableError) return res.status(409).json({ error: err.message });
  return next(err);
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

// Rental listing detail (comes after "/rentals/mine" above so that literal
// segment is never swallowed by ":id").
rentalsRouter.get("/rentals/:id", requireAuth, async (req, res) => {
  const listing = await prisma.rentalListing.findUnique({
    where: { id: req.params.id },
    include: { vehicle: true, driver: { include: { user: true } } },
  });
  if (!listing) return res.status(404).json({ error: "Listing not found" });
  res.json(listing);
});

const bookRentalSchema = z.object({
  startDate: z.string().datetime(),
  endDate: z.string().datetime(),
});

// Customer: reserve a listing for a date range. Days and total price are
// always computed server-side from the listing's current dailyRate — the
// client never asserts a price. The booking is created PENDING_PAYMENT; the
// customer must then call POST /rental-bookings/:id/pay to confirm it.
rentalsRouter.post("/rentals/:id/book", sensitiveLimiter, requireAuth, async (req, res, next) => {
  const parsed = bookRentalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { startDate, endDate } = parsed.data;

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const listing = await prisma.rentalListing.findUnique({ where: { id: req.params.id } });
  if (!listing || listing.status !== "APPROVED") {
    return res.status(409).json({ error: "This vehicle isn't available to book" });
  }

  const start = new Date(startDate);
  const end = new Date(endDate);
  const days = Math.round((end.getTime() - start.getTime()) / MS_PER_DAY);
  if (days < 1) {
    return res.status(400).json({ error: "endDate must be at least one day after startDate" });
  }
  if (start.getTime() < Date.now() - MS_PER_DAY) {
    return res.status(400).json({ error: "startDate can't be in the past" });
  }

  try {
    const booking = await prisma.$transaction(async (tx) => {
      // Prevent double-booking: reject if any other hold (paid or awaiting
      // payment) on this vehicle overlaps the requested range.
      const overlapping = await tx.rentalBooking.findFirst({
        where: {
          listingId: listing.id,
          status: { in: ["PENDING_PAYMENT", "CONFIRMED"] },
          startDate: { lt: end },
          endDate: { gt: start },
        },
      });
      if (overlapping) throw new RentalBookingNotChargeableError("Those dates are no longer available for this vehicle");

      return tx.rentalBooking.create({
        data: {
          renterId: user.id,
          listingId: listing.id,
          startDate: start,
          endDate: end,
          days,
          totalPrice: days * listing.dailyRate,
        },
      });
    });
    res.status(201).json(booking);
  } catch (err) {
    return respondToChargeError(res, err, next);
  }
});

// Customer: my own rental bookings, most recent first.
rentalsRouter.get("/rental-bookings/mine", requireAuth, async (req, res) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const bookings = await prisma.rentalBooking.findMany({
    where: { renterId: user.id },
    include: { listing: { include: { vehicle: true } } },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings);
});

// Customer (who owns the booking): pay for it. CARD returns a Stripe
// clientSecret for the app's PaymentSheet; WALLET debits the customer's own
// prepaid RavelGo Cash balance immediately. Same server-authoritative amount
// (booking.totalPrice) as every other payment path in this codebase.
const payRentalSchema = z.object({ method: z.enum(["CARD", "WALLET"]).default("CARD") });

rentalsRouter.post("/rental-bookings/:id/pay", sensitiveLimiter, requireAuth, async (req, res, next) => {
  const parsed = payRentalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const booking = await prisma.rentalBooking.findUnique({ where: { id: req.params.id } });
  if (!booking) return res.status(404).json({ error: "Booking not found" });
  if (booking.renterId !== user.id) return res.status(403).json({ error: "Not authorized to pay for this booking" });

  try {
    const { booking: updated, clientSecret } = await chargeRentalBooking(booking, parsed.data.method);
    return res.status(201).json(clientSecret ? { ...(updated as object), clientSecret } : updated);
  } catch (err) {
    return respondToChargeError(res, err, next);
  }
});

// Customer (who owns the booking) or Admin: booking detail.
rentalsRouter.get("/rental-bookings/:id", requireAuth, async (req, res) => {
  const booking = await prisma.rentalBooking.findUnique({
    where: { id: req.params.id },
    include: { listing: { include: { vehicle: true } } },
  });
  if (!booking) return res.status(404).json({ error: "Booking not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const user = await findOwnUser(req.user!.sub);
    if (!user || booking.renterId !== user.id) {
      return res.status(403).json({ error: "Not authorized to view this booking" });
    }
  }
  res.json(booking);
});

// Customer (who owns the booking): cancel it. A booking that was already
// paid is refunded (Stripe refund for CARD, a wallet credit for WALLET).
rentalsRouter.patch("/rental-bookings/:id/cancel", requireAuth, async (req, res, next) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const booking = await prisma.rentalBooking.findUnique({ where: { id: req.params.id } });
  if (!booking) return res.status(404).json({ error: "Booking not found" });
  if (booking.renterId !== user.id) return res.status(403).json({ error: "Not authorized to cancel this booking" });

  try {
    const updated = await cancelRentalBooking(booking);
    res.json(updated);
  } catch (err) {
    return respondToChargeError(res, err, next);
  }
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
