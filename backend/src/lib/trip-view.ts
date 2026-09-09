/**
 * Safe trip serialization. Trip responses used to return the raw Prisma object
 * with the full `rider` and `driver.user` relations, leaking email and Cognito
 * subs. This shapes a trip into exactly what the apps need — including the
 * driver summary the rider's "driver found" card renders (P0 #8) — and nothing
 * more. Relations are only included when they were loaded, so it is safe to
 * call on a bare trip too.
 *
 * The key paths the mobile/admin apps read are preserved deliberately:
 * `rider.firstName/lastName` (admin) and `driver.user.firstName/lastName`
 * (rider + admin). Sensitive fields (email, cognitoSub, phone, bank, internal
 * user ids) are never included.
 */

interface UserRel {
  firstName?: string | null;
  lastName?: string | null;
}
interface VehicleRel {
  brand: string;
  model: string;
  colour: string;
  plateNumber: string;
}
interface DriverRel {
  id: string;
  rating?: number | null;
  user?: UserRel | null;
  vehicles?: VehicleRel[] | null;
}
interface TripRel {
  id: string;
  riderId: string;
  driverId: string | null;
  pickup: string;
  destination: string;
  pickupLat?: number | null;
  pickupLng?: number | null;
  dropoffLat?: number | null;
  dropoffLng?: number | null;
  distanceKm?: number | null;
  estimatedFare: number;
  finalFare?: number | null;
  status: string;
  category: string;
  rideCategoryKey?: string | null;
  pickupNote?: string | null;
  riderRating?: number | null;
  requestedAt: Date;
  completedAt?: Date | null;
  arrivedAt?: Date | null;
  commissionRate?: number | null;
  platformCommission?: number | null;
  driverEarnings?: number | null;
  waitingCharge?: number | null;
  cancellationFee?: number | null;
  rider?: UserRel | null;
  driver?: DriverRel | null;
}

export function serializeTrip(trip: TripRel) {
  const driver = trip.driver ?? null;
  const vehicle = driver?.vehicles && driver.vehicles.length > 0 ? driver.vehicles[0] : null;
  return {
    id: trip.id,
    riderId: trip.riderId,
    driverId: trip.driverId,
    pickup: trip.pickup,
    destination: trip.destination,
    pickupLat: trip.pickupLat ?? null,
    pickupLng: trip.pickupLng ?? null,
    dropoffLat: trip.dropoffLat ?? null,
    dropoffLng: trip.dropoffLng ?? null,
    distanceKm: trip.distanceKm ?? null,
    estimatedFare: trip.estimatedFare,
    finalFare: trip.finalFare ?? null,
    status: trip.status,
    category: trip.category,
    rideCategoryKey: trip.rideCategoryKey ?? null,
    pickupNote: trip.pickupNote ?? null,
    riderRating: trip.riderRating ?? null,
    requestedAt: trip.requestedAt,
    completedAt: trip.completedAt ?? null,
    arrivedAt: trip.arrivedAt ?? null,
    commissionRate: trip.commissionRate ?? null,
    platformCommission: trip.platformCommission ?? null,
    driverEarnings: trip.driverEarnings ?? null,
    waitingCharge: trip.waitingCharge ?? null,
    cancellationFee: trip.cancellationFee ?? null,
    rider: trip.rider ? { firstName: trip.rider.firstName ?? null, lastName: trip.rider.lastName ?? null } : undefined,
    driver: driver
      ? {
          id: driver.id,
          rating: driver.rating ?? null,
          user: driver.user ? { firstName: driver.user.firstName ?? null, lastName: driver.user.lastName ?? null } : undefined,
          vehicle: vehicle
            ? { make: vehicle.brand, model: vehicle.model, color: vehicle.colour, plateNumber: vehicle.plateNumber }
            : null,
        }
      : undefined,
  };
}
