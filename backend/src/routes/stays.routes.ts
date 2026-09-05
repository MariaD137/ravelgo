import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { recordAudit } from "../lib/audit";

export const staysRouter = Router();

const MS_PER_NIGHT = 24 * 60 * 60 * 1000;

async function findOwnUser(cognitoSub: string) {
  return prisma.user.findUnique({ where: { cognitoSub } });
}

const createListingSchema = z.object({
  title: z.string().min(1),
  description: z.string().optional(),
  address: z.string().min(1),
  imageUrl: z.string().url().optional(),
  pricePerNight: z.number().positive(),
  maxGuests: z.number().int().positive().max(50).optional(),
});

// Host: list a place for short-stay rental. Any authenticated user can host —
// there's no separate Host role — and new listings need admin approval
// before they're visible to guests, mirroring how RentalListing works.
staysRouter.post("/stays", requireAuth, async (req, res) => {
  const parsed = createListingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const listing = await prisma.propertyListing.create({
    data: { ...parsed.data, hostId: user.id },
  });
  res.status(201).json(listing);
});

// Host: view my own listings, any status.
staysRouter.get("/stays/mine", requireAuth, async (req, res) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const listings = await prisma.propertyListing.findMany({
    where: { hostId: user.id },
    orderBy: { createdAt: "desc" },
  });
  res.json(listings);
});

// Guests/public: browse approved listings. Admins see every listing
// (including pending/rejected) so they can moderate.
staysRouter.get("/stays", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const isAdmin = req.user!.groups.includes("Admin");
  const where = isAdmin ? {} : { status: "APPROVED" as const };

  const [listings, total] = await Promise.all([
    prisma.propertyListing.findMany({
      where,
      include: { host: { select: { firstName: true, lastName: true, email: true } }, _count: { select: { bookings: true } } },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.propertyListing.count({ where }),
  ]);
  // Host email and booking count are only attached for Admin — this list is
  // also the guest-facing browse endpoint above.
  const shaped = listings.map(({ _count, host, ...rest }) => ({
    ...rest,
    host: isAdmin ? host : { firstName: host.firstName, lastName: host.lastName },
    bookingCount: isAdmin ? _count.bookings : undefined,
  }));
  res.json(paginate(shaped, total, page, pageSize));
});

// Guest: my booking history (most recent first).
staysRouter.get("/stays/bookings/mine", requireAuth, async (req, res) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const bookings = await prisma.stayBooking.findMany({
    where: { guestId: user.id },
    include: { property: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings);
});

// Listing detail. Comes after the more specific GET routes above so
// "mine"/"bookings" never get swallowed by :id.
staysRouter.get("/stays/:id", requireAuth, async (req, res) => {
  const listing = await prisma.propertyListing.findUnique({
    where: { id: req.params.id },
    include: { host: { select: { firstName: true, lastName: true, email: true } }, _count: { select: { bookings: true } } },
  });
  if (!listing) return res.status(404).json({ error: "Listing not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  const { _count, host, ...rest } = listing;
  res.json({
    ...rest,
    host: isAdmin ? host : { firstName: host.firstName, lastName: host.lastName },
    bookingCount: isAdmin ? _count.bookings : undefined,
  });
});

const bookSchema = z.object({
  checkIn: z.string().datetime(),
  checkOut: z.string().datetime(),
  guests: z.number().int().positive().max(50),
});

// Guest: book a listing for a date range. Nights and total price are always
// computed server-side from the listing's current pricePerNight — the client
// never asserts a price.
staysRouter.post("/stays/:id/book", requireAuth, async (req, res) => {
  const parsed = bookSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { checkIn, checkOut, guests } = parsed.data;

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User not found" });

  const listing = await prisma.propertyListing.findUnique({ where: { id: req.params.id } });
  if (!listing || listing.status !== "APPROVED") {
    return res.status(409).json({ error: "This listing isn't available to book" });
  }

  const checkInDate = new Date(checkIn);
  const checkOutDate = new Date(checkOut);
  const nights = Math.round((checkOutDate.getTime() - checkInDate.getTime()) / MS_PER_NIGHT);
  if (nights < 1) {
    return res.status(400).json({ error: "checkOut must be at least one night after checkIn" });
  }
  if (guests > listing.maxGuests) {
    return res.status(400).json({ error: `This listing sleeps up to ${listing.maxGuests} guests` });
  }

  const totalPrice = nights * listing.pricePerNight;
  const booking = await prisma.stayBooking.create({
    data: {
      guestId: user.id,
      propertyId: listing.id,
      checkIn: checkInDate,
      checkOut: checkOutDate,
      guests,
      nights,
      totalPrice,
    },
    include: { property: true },
  });
  res.status(201).json(booking);
});

// Admin: bookings made against one listing.
staysRouter.get("/stays/:id/bookings", requireAuth, requireRole("Admin"), async (req, res) => {
  const bookings = await prisma.stayBooking.findMany({
    where: { propertyId: req.params.id },
    include: { guest: { select: { firstName: true, lastName: true, email: true } } },
    orderBy: { createdAt: "desc" },
  });
  res.json(bookings);
});

const decisionSchema = z.object({ status: z.enum(["APPROVED", "REJECTED"]) });

// Admin: approve/reject a listing before it's visible to guests.
staysRouter.patch("/stays/:id/status", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const listing = await prisma.propertyListing.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "STAY_LISTING_REVIEWED",
    entityType: "PropertyListing",
    entityId: listing.id,
    metadata: { status: parsed.data.status },
  });
  res.json(listing);
});
