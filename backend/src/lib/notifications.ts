import { prisma } from "../db/prisma";

/**
 * Real notification types this backend actually emits. Kept as a union
 * (rather than a free string) so every call site is checked against the set
 * the Customer/Driver apps are built to render — no ad hoc type strings.
 */
export type NotificationType =
  | "RIDE_DRIVER_ASSIGNED"
  | "RIDE_STARTED"
  | "RIDE_COMPLETED"
  | "RIDE_CANCELLED"
  | "DELIVERY_COURIER_ASSIGNED"
  | "DELIVERY_PICKED_UP"
  | "DELIVERY_IN_TRANSIT"
  | "DELIVERY_DELIVERED"
  | "DELIVERY_CANCELLED"
  | "RENTAL_CONFIRMED"
  | "RENTAL_CANCELLED"
  | "PAYMENT_SUCCEEDED"
  | "PAYMENT_FAILED";

export type NotificationReferenceType = "TRIP" | "COURIER_REQUEST" | "RENTAL_BOOKING" | "PAYMENT";

/**
 * Create a real, persisted in-app notification for one user. This is the
 * ONLY way a Notification row is ever created — every call site is a real
 * backend event (a status transition, a payment outcome), never a guess or
 * a client-supplied notification.
 *
 * Best-effort, same as recordAudit: a failure to write a notification must
 * never fail (or roll back) the request that triggered it — e.g. a trip
 * really did complete even if the notification insert hiccups.
 */
export async function notifyUser(
  userId: string,
  type: NotificationType,
  title: string,
  body: string,
  reference?: { type: NotificationReferenceType; id: string },
): Promise<void> {
  try {
    await prisma.notification.create({
      data: {
        userId,
        type,
        title,
        body,
        referenceType: reference?.type,
        referenceId: reference?.id,
      },
    });
  } catch (err) {
    console.error("Failed to write notification", err);
  }
}
