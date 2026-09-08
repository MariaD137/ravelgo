import { haversineKm, isValidCoordinate } from "./geo";

/**
 * Safe courier-request serialization. Responses used to return the raw
 * Prisma object with the full `sender` and `driver.user` relations, leaking
 * email, cognitoSub, and other internal fields to any authorized viewer
 * (sender, assigned driver, or admin) — the same class of bug serializeTrip()
 * (trip-view.ts) already fixes for Trip. This shapes a courier request into
 * exactly what the apps need and nothing more.
 *
 * distanceKm is computed here (great-circle, via the same haversineKm used
 * for Trip fares) from pickupLat/Lng + dropoffLat/Lng when both are present —
 * never fabricated, and omitted entirely when either pin is missing.
 *
 * Relations are only included when they were loaded, so this is safe to call
 * on a bare CourierRequest too (e.g. the accept/status-update responses,
 * which never include sender/driver).
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
interface CourierRequestRel {
  id: string;
  senderId: string;
  driverId: string | null;
  pickupAddress: string;
  dropoffAddress: string;
  packageDescription: string;
  packageSize: string;
  recipientName: string;
  recipientPhone: string;
  estimatedFare: number;
  finalFare?: number | null;
  status: string;
  requestedAt: Date;
  pickedUpAt?: Date | null;
  deliveredAt?: Date | null;
  pickupLat?: number | null;
  pickupLng?: number | null;
  dropoffLat?: number | null;
  dropoffLng?: number | null;
  deliveryPhotoUrl?: string | null;
  recipientSignatureUrl?: string | null;
  courierLat?: number | null;
  courierLng?: number | null;
  courierLocationUpdatedAt?: string | null;
  courierPresence?: "LIVE" | "STALE" | null;
  sender?: UserRel | null;
  driver?: DriverRel | null;
}

export function serializeCourierRequest(request: CourierRequestRel) {
  const driver = request.driver ?? null;
  const vehicle = driver?.vehicles && driver.vehicles.length > 0 ? driver.vehicles[0] : null;

  let distanceKm: number | null = null;
  if (
    request.pickupLat != null &&
    request.pickupLng != null &&
    request.dropoffLat != null &&
    request.dropoffLng != null &&
    isValidCoordinate({ lat: request.pickupLat, lng: request.pickupLng }) &&
    isValidCoordinate({ lat: request.dropoffLat, lng: request.dropoffLng })
  ) {
    distanceKm = haversineKm(
      { lat: request.pickupLat, lng: request.pickupLng },
      { lat: request.dropoffLat, lng: request.dropoffLng },
    );
  }

  return {
    id: request.id,
    senderId: request.senderId,
    driverId: request.driverId,
    pickupAddress: request.pickupAddress,
    dropoffAddress: request.dropoffAddress,
    packageDescription: request.packageDescription,
    packageSize: request.packageSize,
    recipientName: request.recipientName,
    recipientPhone: request.recipientPhone,
    estimatedFare: request.estimatedFare,
    finalFare: request.finalFare ?? null,
    status: request.status,
    requestedAt: request.requestedAt,
    pickedUpAt: request.pickedUpAt ?? null,
    deliveredAt: request.deliveredAt ?? null,
    pickupLat: request.pickupLat ?? null,
    pickupLng: request.pickupLng ?? null,
    dropoffLat: request.dropoffLat ?? null,
    dropoffLng: request.dropoffLng ?? null,
    distanceKm,
    deliveryPhotoUrl: request.deliveryPhotoUrl ?? null,
    recipientSignatureUrl: request.recipientSignatureUrl ?? null,
    courierLat: request.courierLat ?? null,
    courierLng: request.courierLng ?? null,
    courierLocationUpdatedAt: request.courierLocationUpdatedAt ?? null,
    courierPresence: request.courierPresence ?? null,
    sender: request.sender
      ? { firstName: request.sender.firstName ?? null, lastName: request.sender.lastName ?? null }
      : undefined,
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
