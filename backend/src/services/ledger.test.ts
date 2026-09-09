import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { setServiceCommissionRate } from "./commission";
import {
  recordDeliveryCommission,
  recordDriverCompensationCharge,
  recordRideCommission,
  reverseCommission,
} from "./ledger";

beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function seedRideFixture() {
  const rider = await prisma.user.create({
    data: { cognitoSub: "ldg-rider", role: "RIDER", firstName: "R", lastName: "L", email: "ldg-rider@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "ldg-driver", role: "DRIVER", firstName: "D", lastName: "L", email: "ldg-driver@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const trip = await prisma.trip.create({
    data: {
      riderId: rider.id,
      driverId: driver.id,
      pickup: "A",
      destination: "B",
      estimatedFare: 5000,
      finalFare: 5000,
      status: "COMPLETED",
    },
  });
  const payment = await prisma.payment.create({
    data: { tripId: trip.id, userId: rider.id, amount: 5000, method: "CARD", status: "SUCCEEDED", paidAt: new Date() },
  });
  return { rider, driverUser, driver, trip, payment };
}

async function seedDeliveryFixture() {
  const sender = await prisma.user.create({
    data: { cognitoSub: "ldg-sender", role: "RIDER", firstName: "S", lastName: "L", email: "ldg-sender@example.com" },
  });
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "ldg-courier", role: "DRIVER", firstName: "C", lastName: "L", email: "ldg-courier@example.com" },
  });
  const driver = await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const request = await prisma.courierRequest.create({
    data: {
      senderId: sender.id,
      driverId: driver.id,
      pickupAddress: "A",
      dropoffAddress: "B",
      packageDescription: "box",
      recipientName: "R",
      recipientPhone: "123",
      estimatedFare: 10000,
      finalFare: 10000,
      status: "DELIVERED",
    },
  });
  const payment = await prisma.payment.create({
    data: { courierRequestId: request.id, userId: sender.id, amount: 10000, method: "CARD", status: "SUCCEEDED", paidAt: new Date() },
  });
  return { sender, driverUser, driver, request, payment };
}

test("recordRideCommission: ₦5,000 @ 20% locks in RavelGo ₦1,000 / driver ₦4,000 on the trip and the ledger", async () => {
  await setServiceCommissionRate("RIDE", 0.2, "admin@example.com");
  const { trip, payment, driver, rider } = await seedRideFixture();

  await recordRideCommission(trip, payment);

  const updated = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(updated.commissionRate, 0.2);
  assert.equal(updated.platformCommission, 1000);
  assert.equal(updated.driverEarnings, 4000);

  const ledgerRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "RIDE_FARE" } });
  assert.equal(ledgerRow.grossAmount, 5000);
  assert.equal(ledgerRow.commissionAmount, 1000);
  assert.equal(ledgerRow.driverEarnings, 4000);
  assert.equal(ledgerRow.driverId, driver.id);
  assert.equal(ledgerRow.customerId, rider.id);
  assert.equal(ledgerRow.status, "SETTLED");
});

test("recordRideCommission is idempotent — calling it twice for the same trip writes only one ledger row", async () => {
  const { trip, payment } = await seedRideFixture();
  await recordRideCommission(trip, payment);
  await recordRideCommission(trip, payment);

  const rows = await prisma.financialTransaction.findMany({ where: { tripId: trip.id, type: "RIDE_FARE" } });
  assert.equal(rows.length, 1);
});

test("recordDeliveryCommission: ₦10,000 @ 20% locks in RavelGo ₦2,000 / driver ₦8,000", async () => {
  await setServiceCommissionRate("DELIVERY", 0.2, "admin@example.com");
  const { request, payment } = await seedDeliveryFixture();

  await recordDeliveryCommission(request, payment);

  const updated = await prisma.courierRequest.findUniqueOrThrow({ where: { id: request.id } });
  assert.equal(updated.commissionRate, 0.2);
  assert.equal(updated.platformCommission, 2000);
  assert.equal(updated.driverEarnings, 8000);

  const ledgerRow = await prisma.financialTransaction.findFirstOrThrow({
    where: { courierRequestId: request.id, type: "DELIVERY_FARE" },
  });
  assert.equal(ledgerRow.grossAmount, 10000);
  assert.equal(ledgerRow.commissionAmount, 2000);
  assert.equal(ledgerRow.driverEarnings, 8000);
});

test("commission is immutable after settlement — a later rate change never touches an already-settled transaction", async () => {
  await setServiceCommissionRate("RIDE", 0.2, "admin@example.com");
  const { trip, payment } = await seedRideFixture();
  await recordRideCommission(trip, payment);

  // Admin drops the rate to 18% AFTER this trip already settled.
  await setServiceCommissionRate("RIDE", 0.18, "admin@example.com");

  const stillOriginal = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(stillOriginal.commissionRate, 0.2);
  assert.equal(stillOriginal.platformCommission, 1000);
  assert.equal(stillOriginal.driverEarnings, 4000);

  const ledgerRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "RIDE_FARE" } });
  assert.equal(ledgerRow.commissionRate, 0.2);

  // A NEW trip settling now uses the new rate.
  const { trip: trip2, payment: payment2 } = await seedRideFixture();
  await recordRideCommission(trip2, payment2);
  const updated2 = await prisma.trip.findUniqueOrThrow({ where: { id: trip2.id } });
  assert.equal(updated2.commissionRate, 0.18);
});

test("recordDriverCompensationCharge (waiting/cancellation) is never commissioned — 100% goes to the driver", async () => {
  const { trip, driver, rider } = await seedRideFixture();
  await recordDriverCompensationCharge({
    type: "WAITING_CHARGE",
    tripId: trip.id,
    customerId: rider.id,
    driverId: driver.id,
    amount: 150,
  });

  const row = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "WAITING_CHARGE" } });
  assert.equal(row.commissionRate, 0);
  assert.equal(row.commissionAmount, 0);
  assert.equal(row.driverEarnings, 150);
});

test("reverseCommission: a full refund reverses the commission and zeroes the trip's driver-facing figures", async () => {
  const { trip, payment } = await seedRideFixture();
  await recordRideCommission(trip, payment, 5000); // 20% default -> 1000/4000

  await reverseCommission({ tripId: trip.id, refundAmount: 5000, reason: "rider dispute" });

  const refundRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "REFUND" } });
  assert.equal(refundRow.commissionAmount, -1000);
  assert.equal(refundRow.driverEarnings, -4000);

  const updatedTrip = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(updatedTrip.platformCommission, 0);
  assert.equal(updatedTrip.driverEarnings, 0);
});

test("reverseCommission: a partial refund reverses proportionally", async () => {
  const { trip, payment } = await seedRideFixture();
  await recordRideCommission(trip, payment, 5000); // 1000/4000

  // Refund half the fare.
  await reverseCommission({ tripId: trip.id, refundAmount: 2500, reason: "partial goodwill credit" });

  const refundRow = await prisma.financialTransaction.findFirstOrThrow({ where: { tripId: trip.id, type: "REFUND" } });
  assert.equal(refundRow.commissionAmount, -500);
  assert.equal(refundRow.driverEarnings, -2000);

  // Partial refund leaves the trip's own summary fields as the original split.
  const updatedTrip = await prisma.trip.findUniqueOrThrow({ where: { id: trip.id } });
  assert.equal(updatedTrip.platformCommission, 1000);
  assert.equal(updatedTrip.driverEarnings, 4000);
});

test("reverseCommission is a no-op when nothing was ever settled for the trip", async () => {
  const { trip } = await seedRideFixture();
  // No recordRideCommission call — nothing settled yet.
  await reverseCommission({ tripId: trip.id, refundAmount: 5000, reason: "n/a" });
  const rows = await prisma.financialTransaction.findMany({ where: { tripId: trip.id } });
  assert.equal(rows.length, 0);
});
