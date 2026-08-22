import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { releaseDriver, reserveDriver } from "./driver-availability";

export class RentalOverlapConflict extends Error {
  constructor(message = "Vehicle is already booked for an overlapping date range") {
    super(message);
    this.name = "RentalOverlapConflict";
  }
}

export class RentalBookingStateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RentalBookingStateError";
  }
}

// Which existing bookings block a new one from being created for the same
// vehicle. REQUESTED is deliberately excluded — an unconfirmed request
// shouldn't be able to lock out every other renter's request for the same
// dates; only a booking the driver has actually committed to (CONFIRMED) or
// that is physically underway (ACTIVE) blocks an overlapping range. This is
// a documented product choice, not a discovered business rule — flagged in
// the final report as BUSINESS DECISION REQUIRED if product wants
// REQUESTED to also block.
const OVERLAP_BLOCKING_STATUSES = ["CONFIRMED", "ACTIVE"] as const;

export interface CreateBookingInput {
  rentalListingId: string;
  renterId: string;
  startAt: Date;
  endAt: Date;
}

/**
 * Creates a rental booking for an APPROVED listing, rejecting any date
 * range that overlaps an existing CONFIRMED/ACTIVE booking for the same
 * vehicle. The overlap check and the insert run inside one SERIALIZABLE
 * transaction — never "if available then create" as two separate
 * statements, which would let two concurrent bookings both pass the check
 * before either commits (Part 12).
 *
 * price is computed directly from the listing's own dailyRate × the number
 * of days requested — the one arithmetic this data model already defines,
 * not an invented pricing/commission scheme (see PricingRule/SurgeZone,
 * which this rental flow deliberately does not touch or duplicate).
 */
export async function createBooking(input: CreateBookingInput) {
  if (input.startAt >= input.endAt) {
    throw new RentalBookingStateError("startAt must be before endAt");
  }

  try {
    return await prisma.$transaction(
      async (tx) => {
        const listing = await tx.rentalListing.findUnique({ where: { id: input.rentalListingId } });
        if (!listing) throw new RentalBookingStateError("Rental listing not found");
        if (listing.status !== "APPROVED") {
          throw new RentalBookingStateError("Rental listing is not approved for booking");
        }

        const overlapping = await tx.rentalBooking.findFirst({
          where: {
            vehicleId: listing.vehicleId,
            status: { in: [...OVERLAP_BLOCKING_STATUSES] },
            startAt: { lt: input.endAt },
            endAt: { gt: input.startAt },
          },
        });
        if (overlapping) throw new RentalOverlapConflict();

        const days = Math.max(1, Math.ceil((input.endAt.getTime() - input.startAt.getTime()) / 86_400_000));

        return tx.rentalBooking.create({
          data: {
            rentalListingId: listing.id,
            renterId: input.renterId,
            vehicleId: listing.vehicleId,
            startAt: input.startAt,
            endAt: input.endAt,
            price: listing.dailyRate * days,
          },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      throw new RentalOverlapConflict();
    }
    throw err;
  }
}

/** Driver (the listing's owner) confirms or rejects a REQUESTED booking. No
 * driver reservation happens yet — confirming a future booking doesn't make
 * the driver operationally busy today (Part 2: listing/booking approval is
 * not the same as active usage). Reservation only happens at activation. */
export async function decideBooking(bookingId: string, status: "CONFIRMED" | "REJECTED") {
  const { count } = await prisma.rentalBooking.updateMany({
    where: { id: bookingId, status: "REQUESTED" },
    data: { status },
  });
  if (count === 0) {
    throw new RentalBookingStateError("Booking is not in a REQUESTED state");
  }
  return prisma.rentalBooking.findUniqueOrThrow({ where: { id: bookingId } });
}

/**
 * Marks a CONFIRMED booking ACTIVE (the rental handover has actually
 * happened) and reserves the driver via the shared DriverAssignment table —
 * this is the one rental transition that makes the driver operationally
 * occupied, distinct from merely listing or confirming a future booking.
 */
export async function activateBooking(bookingId: string, driverId: string) {
  try {
    return await prisma.$transaction(
      async (tx) => {
        const { count } = await tx.rentalBooking.updateMany({
          where: { id: bookingId, status: "CONFIRMED" },
          data: { status: "ACTIVE" },
        });
        if (count === 0) {
          throw new RentalBookingStateError("Booking is not in a CONFIRMED state");
        }

        const booking = await tx.rentalBooking.findUniqueOrThrow({ where: { id: bookingId } });
        await reserveDriver(tx, {
          driverId,
          assignmentType: "RENTAL",
          assignmentId: booking.id,
          vehicleId: booking.vehicleId,
        });
        return booking;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      throw new RentalBookingStateError("Booking activation conflicted with a concurrent change, retry");
    }
    throw err;
  }
}

/** Ends a booking (COMPLETED or CANCELLED) and releases the driver's active
 * RENTAL assignment if one exists — a no-op release if the booking never
 * reached ACTIVE (e.g. cancelled while still REQUESTED/CONFIRMED). */
export async function endBooking(bookingId: string, status: "COMPLETED" | "CANCELLED", driverId: string) {
  return prisma.$transaction(async (tx) => {
    const updated = await tx.rentalBooking.update({ where: { id: bookingId }, data: { status } });
    await releaseDriver(tx, { driverId, assignmentType: "RENTAL", assignmentId: bookingId });
    return updated;
  });
}
