import { env } from "../config/env";

/**
 * Safe vehicle/rental-listing serialization, mirroring trip-view.ts's
 * serializeTrip() and courier-view.ts's serializeCourierRequest(). Rental
 * responses used to return the raw Prisma object with the full `driver.user`
 * relation, leaking email and cognitoSub to any rider browsing listings.
 *
 * photoUrl is built from Vehicle.photoKey + the assets bucket's CloudFront
 * domain (ASSETS_CDN_DOMAIN) — never a raw S3 URL, and never fabricated: a
 * vehicle with no photoKey, or a deploy with no CDN domain configured, gets
 * photoUrl: null rather than a broken link.
 */

interface UserRel {
  firstName?: string | null;
  lastName?: string | null;
}
interface DriverRel {
  id: string;
  rating?: number | null;
  user?: UserRel | null;
}
interface VehicleRel {
  id: string;
  driverId: string;
  brand: string;
  model: string;
  colour: string;
  plateNumber: string;
  year: string;
  isPrimary: boolean;
  listedForRental: boolean;
  vehicleClass?: string | null;
  photoKey?: string | null;
  createdAt: Date;
}
interface RentalBookingRel {
  id: string;
  startDate: Date;
  endDate: Date;
  days: number;
  totalPrice: number;
  status: string;
  paymentStatus: string;
  createdAt: Date;
  renter?: UserRel | null;
}
interface RentalListingRel {
  id: string;
  driverId: string;
  vehicleId: string;
  dailyRate: number;
  location: string;
  lat?: number | null;
  lng?: number | null;
  status: string;
  createdAt: Date;
  vehicle?: VehicleRel | null;
  driver?: DriverRel | null;
  // Only ever populated for the owning driver's own "my listings" view
  // (GET /rentals/mine) — never for the public browse listing.
  bookings?: RentalBookingRel[] | null;
}

// The renter's identity is stripped to first/last name only, the same
// minimal-PII bar every other counterparty view in this codebase uses
// (serializeTrip's rider, serializeCourierRequest's sender) — the vehicle
// owner needs to know WHO booked their car, never their email or Cognito sub.
function serializeRentalBooking(booking: RentalBookingRel) {
  return {
    id: booking.id,
    startDate: booking.startDate,
    endDate: booking.endDate,
    days: booking.days,
    totalPrice: booking.totalPrice,
    status: booking.status,
    paymentStatus: booking.paymentStatus,
    createdAt: booking.createdAt,
    renter: booking.renter
      ? { firstName: booking.renter.firstName ?? null, lastName: booking.renter.lastName ?? null }
      : undefined,
  };
}

export function photoUrlFor(photoKey: string | null | undefined): string | null {
  if (!photoKey || !env.ASSETS_CDN_DOMAIN) return null;
  return `https://${env.ASSETS_CDN_DOMAIN}/${photoKey}`;
}

export function serializeVehicle(vehicle: VehicleRel) {
  return {
    id: vehicle.id,
    driverId: vehicle.driverId,
    brand: vehicle.brand,
    model: vehicle.model,
    colour: vehicle.colour,
    plateNumber: vehicle.plateNumber,
    year: vehicle.year,
    isPrimary: vehicle.isPrimary,
    listedForRental: vehicle.listedForRental,
    vehicleClass: vehicle.vehicleClass ?? null,
    photoUrl: photoUrlFor(vehicle.photoKey),
    createdAt: vehicle.createdAt,
  };
}

export function serializeRentalListing(listing: RentalListingRel) {
  return {
    id: listing.id,
    driverId: listing.driverId,
    vehicleId: listing.vehicleId,
    dailyRate: listing.dailyRate,
    location: listing.location,
    lat: listing.lat ?? null,
    lng: listing.lng ?? null,
    status: listing.status,
    createdAt: listing.createdAt,
    vehicle: listing.vehicle ? serializeVehicle(listing.vehicle) : undefined,
    driver: listing.driver
      ? {
          id: listing.driver.id,
          rating: listing.driver.rating ?? null,
          user: listing.driver.user
            ? { firstName: listing.driver.user.firstName ?? null, lastName: listing.driver.user.lastName ?? null }
            : undefined,
        }
      : undefined,
    bookings: listing.bookings ? listing.bookings.map(serializeRentalBooking) : undefined,
  };
}
