/**
 * The commission/earnings ledger. Writes here are the only place a
 * FinancialTransaction row is created, and the only place Trip/CourierRequest
 * commission fields are set — always at the moment a Payment actually
 * settles (SUCCEEDED), never at trip/delivery COMPLETED (the money hasn't
 * moved yet at that point) and never recomputed later from whatever the
 * current commission config says (spec #14: immutable after settlement).
 */

import type { CourierRequest, Payment, Prisma, Trip } from "@prisma/client";
import { prisma } from "../db/prisma";
import { resolveCommissionRate, splitCommission } from "./commission";

type RideForLedger = Pick<Trip, "id" | "riderId" | "driverId" | "rideCategoryKey">;
type DeliveryForLedger = Pick<CourierRequest, "id" | "senderId" | "driverId" | "deliveryVehicleClass">;
type PaymentForLedger = Pick<Payment, "id" | "amount" | "method">;

/**
 * Record a ride's commission the moment its payment settles. Idempotent: a
 * retried Paystack webhook delivery, or a caller invoked twice, never creates
 * a second RIDE_FARE row for the same trip.
 *
 * `fareAmount` — defaulting to the full payment amount — is the commissioned
 * portion specifically: when a settled Payment also bundles a
 * waiting/cancellation charge (100% driver, never commissioned — see
 * recordDriverCompensationCharge below), callers pass the fare-only amount
 * here so this ledger row's grossAmount never overstates what RavelGo
 * actually takes a cut of.
 */
export async function recordRideCommission(
  trip: RideForLedger,
  payment: PaymentForLedger,
  fareAmount: number = payment.amount,
): Promise<void> {
  const existing = await prisma.financialTransaction.findFirst({
    where: { tripId: trip.id, type: "RIDE_FARE" },
  });
  if (existing) return;

  let categoryOverride: number | null = null;
  if (trip.rideCategoryKey) {
    const category = await prisma.rideCategory.findUnique({ where: { key: trip.rideCategoryKey } });
    categoryOverride = category?.commissionRate ?? null;
  }
  const rate = await resolveCommissionRate("RIDE", categoryOverride);
  const split = splitCommission(fareAmount, rate);

  await prisma.$transaction([
    prisma.trip.update({
      where: { id: trip.id },
      data: {
        commissionRate: split.commissionRate,
        platformCommission: split.commissionAmount,
        driverEarnings: split.driverEarnings,
      },
    }),
    prisma.financialTransaction.create({
      data: {
        type: "RIDE_FARE",
        tripId: trip.id,
        paymentId: payment.id,
        customerId: trip.riderId,
        driverId: trip.driverId,
        grossAmount: fareAmount,
        commissionRate: split.commissionRate,
        commissionAmount: split.commissionAmount,
        driverEarnings: split.driverEarnings,
        paymentMethod: payment.method,
        status: "SETTLED",
        completedAt: new Date(),
      },
    }),
  ]);
}

/** Same guarantee as recordRideCommission, for a delivery. */
export async function recordDeliveryCommission(
  request: DeliveryForLedger,
  payment: PaymentForLedger,
  fareAmount: number = payment.amount,
): Promise<void> {
  const existing = await prisma.financialTransaction.findFirst({
    where: { courierRequestId: request.id, type: "DELIVERY_FARE" },
  });
  if (existing) return;

  let categoryOverride: number | null = null;
  if (request.deliveryVehicleClass) {
    const rateRow = await prisma.deliveryVehicleRate.findUnique({ where: { vehicleClass: request.deliveryVehicleClass } });
    categoryOverride = rateRow?.commissionRate ?? null;
  }
  const rate = await resolveCommissionRate("DELIVERY", categoryOverride);
  const split = splitCommission(fareAmount, rate);

  await prisma.$transaction([
    prisma.courierRequest.update({
      where: { id: request.id },
      data: {
        commissionRate: split.commissionRate,
        platformCommission: split.commissionAmount,
        driverEarnings: split.driverEarnings,
      },
    }),
    prisma.financialTransaction.create({
      data: {
        type: "DELIVERY_FARE",
        courierRequestId: request.id,
        paymentId: payment.id,
        customerId: request.senderId,
        driverId: request.driverId,
        grossAmount: fareAmount,
        commissionRate: split.commissionRate,
        commissionAmount: split.commissionAmount,
        driverEarnings: split.driverEarnings,
        paymentMethod: payment.method,
        status: "SETTLED",
        completedAt: new Date(),
      },
    }),
  ]);
}

/**
 * A driver-compensation charge (waiting time or a rider-caused cancellation)
 * — recorded for audit/transparency but deliberately NOT commissioned (see
 * commission.ts doc comment): the full amount goes to the driver, since it
 * compensates their real lost time rather than being part of the fare RavelGo
 * takes a cut of.
 */
export async function recordDriverCompensationCharge(params: {
  type: "CANCELLATION_FEE" | "WAITING_CHARGE";
  tripId?: string;
  courierRequestId?: string;
  customerId: string;
  driverId: string;
  amount: number;
  paymentMethod?: "CARD" | "CASH" | "WALLET" | null;
}): Promise<void> {
  if (params.amount <= 0) return;
  await prisma.financialTransaction.create({
    data: {
      type: params.type,
      tripId: params.tripId,
      courierRequestId: params.courierRequestId,
      customerId: params.customerId,
      driverId: params.driverId,
      grossAmount: params.amount,
      commissionRate: 0,
      commissionAmount: 0,
      driverEarnings: params.amount,
      paymentMethod: params.paymentMethod ?? undefined,
      status: "SETTLED",
      completedAt: new Date(),
    },
  });
}

/**
 * Reverse a settled RIDE_FARE/DELIVERY_FARE transaction after a refund
 * (full or partial). Appends a REFUND row rather than mutating the original
 * — the ledger stays append-only and both the charge and its reversal are
 * permanently auditable. A full refund also zeroes the driver-facing
 * commission/earnings fields on the parent Trip/CourierRequest so its
 * receipt stops showing money that was given back; a partial refund leaves
 * those fields as-is (the original breakdown) and relies on the ledger for
 * the accurate net picture.
 */
export async function reverseCommission(params: {
  tripId?: string;
  courierRequestId?: string;
  refundAmount: number;
  reason: string;
}): Promise<void> {
  const original = await prisma.financialTransaction.findFirst({
    where: {
      tripId: params.tripId,
      courierRequestId: params.courierRequestId,
      type: params.tripId ? "RIDE_FARE" : "DELIVERY_FARE",
      status: "SETTLED",
    },
  });
  // Nothing was ever settled for this trip/delivery (e.g. it was cancelled
  // before any payment existed) — there is no commission to reverse.
  if (!original) return;

  const proportion = original.grossAmount > 0 ? Math.min(1, Math.max(0, params.refundAmount / original.grossAmount)) : 0;
  const reversedCommission = Math.round(original.commissionAmount * proportion * 100) / 100;
  const reversedEarnings = Math.round(original.driverEarnings * proportion * 100) / 100;
  const isFullRefund = proportion >= 0.999;

  const ops: Prisma.PrismaPromise<unknown>[] = [
    prisma.financialTransaction.create({
      data: {
        type: "REFUND",
        tripId: params.tripId,
        courierRequestId: params.courierRequestId,
        customerId: original.customerId,
        driverId: original.driverId,
        grossAmount: params.refundAmount,
        commissionRate: original.commissionRate,
        commissionAmount: -reversedCommission,
        driverEarnings: -reversedEarnings,
        currency: original.currency,
        paymentMethod: original.paymentMethod,
        status: "SETTLED",
        reversalOfId: original.id,
        metadata: { reason: params.reason },
        completedAt: new Date(),
      },
    }),
  ];
  if (isFullRefund && params.tripId) {
    ops.push(prisma.trip.update({ where: { id: params.tripId }, data: { platformCommission: 0, driverEarnings: 0 } }));
  } else if (isFullRefund && params.courierRequestId) {
    ops.push(
      prisma.courierRequest.update({
        where: { id: params.courierRequestId },
        data: { platformCommission: 0, driverEarnings: 0 },
      }),
    );
  }
  await prisma.$transaction(ops);
}
