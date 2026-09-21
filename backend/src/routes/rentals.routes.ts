import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { containsInsensitive, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { notifyUser } from "../lib/notifications";
import { InsufficientFundsError } from "../services/wallet";
import {
  RentalBookingNotChargeableError,
  cancelRentalBooking,
  chargeRentalBooking,
  reconcileExpiredRentalBookings,
} from "../services/rental-payment";
import { serializeRentalListing, serializeVehicle } from "../lib/vehicle-view";

export const rentalsRouter = Router();

const MS_PER_DAY = 24 * 60 * 60 * 1000;

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

async function findOwnUser(cognitoSub: string) {
  return prisma.user.findUnique({ where: { cognitoSub } });
}

// A booking's nested listing.vehicle never carries a driver.user relation at
// this call depth, so there's no PII to strip here — just run photoKeys
// through the same public-URL builder every other vehicle response uses.
function withVehiclePhotoUrl<T extends { listing: { vehicle: Parameters<typeof serializeVehicle>[0] } & Record<string, unknown> }>(
  booking: T,
) {
  return { ...booking, listing: { ...booking.listing, vehicle: serializeVehicle(booking.listing.vehicle) } };
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
  // Populated by the app's Places-backed address search. Optional so a
  // client on an older build (or one that hits this without the picker) can
  // still list a vehicle — the listing just won't have coordinates yet.
  lat: z.number().finite().min(-90).max(90).optional(),
  lng: z.number().finite().min(-180).max(180).optional(),
});

// Driver: list a vehicle for luxury rental. Gated on the same admin-approved
// ACTIVE status as ride/delivery matching — a PENDING_REVIEW driver can
// manage their profile and documents, but can't yet offer provider services.
rentalsRouter.post("/rentals", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = createRentalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  if (driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account must be approved before you can list a vehicle for rental." });
  }

  const vehicle = await prisma.vehicle.findUnique({ where: { id: parsed.data.vehicleId } });
  if (!vehicle || vehicle.driverId !== driver.id) {
    return res.status(404).json({ error: "Vehicle not found" });
  }

  const listing = await prisma.rentalListing.create({
    data: { ...parsed.data, driverId: driver.id },
  });
  await prisma.vehicle.update({ where: { id: vehicle.id }, data: { listedForRental: true } });

  res.status(201).json(serializeRentalListing(listing));
});

// Driver: view my own rental listings, WITH their bookings (dates, status,
// payment status, and the renter's name only — never email/phone/cognitoSub)
// so the owner can actually see who booked their car and when, not just that
// a listing exists. This is the one place bookings are attached to a
// listing response — the public /rentals browse list never includes them.
rentalsRouter.get("/rentals/mine", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  // Opportunistic reconciliation (see reconcileExpiredRentalBookings' doc
  // comment) so the owner never sees a booking still marked CONFIRMED after
  // its dates have actually passed, even if the periodic sweep hasn't run
  // yet.
  await reconcileExpiredRentalBookings();

  const listings = await prisma.rentalListing.findMany({
    where: { driverId: driver.id },
    include: {
      vehicle: true,
      bookings: { include: { renter: true }, orderBy: { startDate: "desc" } },
    },
    orderBy: { createdAt: "desc" },
  });
  res.json(listings.map(serializeRentalListing));
});

// Riders/public: browse approved rental listings. Admin callers additionally
// get ?q= server-side search (listing id, vehicle plate/brand/model, or the
// owning driver's name/email) — riders browse by location/price elsewhere,
// so search stays admin-only rather than adding a param with no real use for
// the public browse case.
rentalsRouter.get("/rentals", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.merge(searchQuerySchema).safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, q } = parsed.data;

  const groups = req.user!.groups;
  const isAdmin = groups.includes("Admin");
  const where: Prisma.RentalListingWhereInput = {
    ...(isAdmin ? {} : { status: "APPROVED" as const }),
    ...(isAdmin && q
      ? {
          OR: [
            { id: containsInsensitive(q) },
            { vehicle: { plateNumber: containsInsensitive(q) } },
            { vehicle: { brand: containsInsensitive(q) } },
            { vehicle: { model: containsInsensitive(q) } },
            { driver: { user: { firstName: containsInsensitive(q) } } },
            { driver: { user: { lastName: containsInsensitive(q) } } },
            { driver: { user: { email: containsInsensitive(q) } } },
          ],
        }
      : {}),
  };

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
  res.json(paginate(listings.map(serializeRentalListing), total, page, pageSize));
});

// Rental listing detail (comes after "/rentals/mine" above so that literal
// segment is never swallowed by ":id").
rentalsRouter.get("/rentals/:id", requireAuth, async (req, res) => {
  const listing = await prisma.rentalListing.findUnique({
    where: { id: req.params.id },
    include: { vehicle: true, driver: { include: { user: true } } },
  });
  if (!listing) return res.status(404).json({ error: "Listing not found" });
  res.json(serializeRentalListing(listing));
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

  await reconcileExpiredRentalBookings();

  const bookings = await prisma.rentalBooking.findMany({
    where: { renterId: user.id },
    include: { listing: { include: { vehicle: true } } },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings.map(withVehiclePhotoUrl));
});

// Customer (who owns the booking): pay for it. CARD returns a Paystack
// authorizationUrl for the app to complete; WALLET debits the customer's own
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
    const { booking: updated, authorizationUrl } = await chargeRentalBooking(booking, parsed.data.method);
    return res.status(201).json(authorizationUrl ? { ...(updated as object), authorizationUrl } : updated);
  } catch (err) {
    return respondToChargeError(res, err, next);
  }
});

// Customer (who owns the booking) or Admin: booking detail.
rentalsRouter.get("/rental-bookings/:id", requireAuth, async (req, res) => {
  await reconcileExpiredRentalBookings();

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
  res.json(withVehiclePhotoUrl(booking));
});

// Customer (who owns the booking): cancel it. A booking that was already
// paid is refunded (Paystack refund for CARD, a wallet credit for WALLET).
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

const decisionSchema = z
  .object({
    status: z.enum(["APPROVED", "REJECTED"]),
    // Required (and validated non-empty after trimming) only when rejecting —
    // enforced below rather than with a discriminated union so the 400 names
    // the real reason instead of a generic schema-shape error. Same pattern
    // as documents.routes.ts's reviewSchema.
    rejectionReason: z.string().trim().max(1000).optional(),
  })
  .refine((data) => data.status !== "REJECTED" || !!data.rejectionReason, {
    message: "A rejection reason is required.",
    path: ["rejectionReason"],
  });

// Admin (Super Admin / Operations Manager): approve/reject a rental listing
rentalsRouter.patch("/rentals/:id/status", requireAuth, requireAdminPermission("listings:write"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.rentalListing.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Rental listing not found" });

  const listing = await prisma.rentalListing.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      // Cleared back to null on approval so a reason never lingers on a
      // listing that isn't actually rejected (same convention as
      // DriverDocument.rejectionReason).
      rejectionReason: parsed.data.status === "REJECTED" ? parsed.data.rejectionReason : null,
    },
  });
  // Awaited (unlike most recordAudit call sites) so a caller can never
  // observe a 200 for this admin action before the audit row actually
  // exists — recordAudit never throws, so this can't turn a real failure
  // into one; it only guarantees ordering for the test/audit-trail guarantee.
  await recordAudit({
    actorSub: req.user!.sub,
    action: "RENTAL_LISTING_REVIEWED",
    entityType: "RentalListing",
    entityId: listing.id,
    metadata: { status: parsed.data.status, rejectionReason: parsed.data.rejectionReason },
  });
  // Told to the driver, not just recorded in the audit log — this decision
  // previously left no trace the submitting driver could ever see.
  const driver = await prisma.driver.findUnique({ where: { id: listing.driverId } });
  if (driver) {
    await notifyUser(
      driver.userId,
      "RENTAL_LISTING_REVIEWED",
      parsed.data.status === "APPROVED" ? "Rental listing approved" : "Rental listing rejected",
      parsed.data.status === "APPROVED"
        ? "Your rental listing has been approved and is now visible to riders."
        : `Your rental listing was rejected: ${parsed.data.rejectionReason}`,
      { type: "RENTAL_LISTING", id: listing.id },
    );
  }
  res.json(listing);
});
