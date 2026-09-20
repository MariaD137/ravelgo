import { prisma } from "../db/prisma";
import { sendPushToUser } from "../services/push";

/**
 * Real notification types this backend actually emits. Kept as a union
 * (rather than a free string) so every call site is checked against the set
 * the Customer/Driver apps are built to render — no ad hoc type strings.
 */
export type NotificationType =
  | "RIDE_OFFERED"
  | "RIDE_DRIVER_ASSIGNED"
  | "RIDE_DRIVER_ARRIVED"
  | "RIDE_STARTED"
  | "RIDE_COMPLETED"
  | "RIDE_CANCELLED"
  | "DELIVERY_OFFERED"
  | "DELIVERY_COURIER_ASSIGNED"
  | "DELIVERY_PICKED_UP"
  | "DELIVERY_IN_TRANSIT"
  | "DELIVERY_DELIVERED"
  | "DELIVERY_CANCELLED"
  | "RENTAL_CONFIRMED"
  | "RENTAL_COMPLETED"
  | "RENTAL_CANCELLED"
  | "PAYMENT_SUCCEEDED"
  | "PAYMENT_FAILED"
  | "ADMIN_PAYMENT_FAILED"
  | "ADMIN_SAFETY_ALERT_RAISED"
  | "ADMIN_TRIP_DISPUTED"
  | "DRIVER_ACCOUNT_STATUS_CHANGED"
  | "PAYOUT_COMPLETED"
  | "PAYOUT_FAILED"
  // Both sides of a referral that just paid out (services/referral.ts).
  | "REFERRAL_REWARDED";

export type NotificationReferenceType =
  | "TRIP"
  | "COURIER_REQUEST"
  | "RENTAL_BOOKING"
  | "PAYMENT"
  | "EMERGENCY_ALERT"
  | "PAYOUT";

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
  let notificationId: string | undefined;
  try {
    const notification = await prisma.notification.create({
      data: {
        userId,
        type,
        title,
        body,
        referenceType: reference?.type,
        referenceId: reference?.id,
      },
    });
    notificationId = notification.id;
  } catch (err) {
    console.error("Failed to write notification", err);
  }

  // Device push is additive, best-effort fan-out on top of the persisted
  // row above — it never blocks or fails the real event that triggered it,
  // and it still runs even if the persisted-row write itself failed (the
  // customer still gets *a* notification even if history-listing wouldn't
  // show it). The data payload lets the Customer App navigate on tap the
  // same way an in-app notification tap does.
  await sendPushToUser(userId, title, body, {
    type,
    ...(notificationId ? { notificationId } : {}),
    ...(reference ? { referenceType: reference.type, referenceId: reference.id } : {}),
  });
}

/**
 * Fan out a real event to every Admin-role user (AA-2), reusing notifyUser()
 * per recipient so each admin gets the same persisted row + best-effort
 * device push a rider/driver would. There is no "admin broadcast" table —
 * this is simply notifyUser() called once per current Role.ADMIN row, so a
 * newly created admin starts receiving future events with zero extra setup
 * and a deactivated one (if ever added) would stop automatically.
 */
export async function notifyAllAdmins(
  type: NotificationType,
  title: string,
  body: string,
  reference?: { type: NotificationReferenceType; id: string },
): Promise<void> {
  const admins = await prisma.user.findMany({ where: { role: "ADMIN" }, select: { id: true } });
  await Promise.all(admins.map((admin) => notifyUser(admin.id, type, title, body, reference)));
}
