import { mock } from "node:test";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";

export interface MockCognitoUser {
  sub: string;
  email?: string;
  groups?: string[];
}

/**
 * Stubs the shared Cognito verifier singleton so route tests can authenticate
 * as an arbitrary user/role without a real Cognito user pool or JWT. Returns
 * the bearer token string to send as `Authorization: Bearer <token>`.
 */
export function mockAuthAs(user: MockCognitoUser): string {
  const token = `mock.${user.sub}`;
  mock.method(verifier, "verify", async (candidate: string) => {
    if (candidate !== token) {
      throw new Error("invalid token");
    }
    return {
      sub: user.sub,
      email: user.email,
      "cognito:groups": user.groups ?? [],
    } as never;
  });
  return token;
}

export function restoreAuth() {
  mock.restoreAll();
}

/**
 * Stubs stripeClient.paymentIntents.create so route tests never make a real
 * network call to Stripe — returns a fake PaymentIntent id/clientSecret,
 * same pattern as mockAuthAs() for the Cognito verifier.
 */
export function mockPaymentIntentCreate(id = `pi_test_${Date.now()}`) {
  mock.method(stripeClient.paymentIntents, "create", async () => ({
    id,
    client_secret: `${id}_secret_test`,
  }));
  return id;
}

// Delete in FK-safe order (children before parents).
export async function resetDb() {
  await prisma.walletTransaction.deleteMany();
  await prisma.walletAccount.deleteMany();
  await prisma.payment.deleteMany();
  await prisma.emergencyAlert.deleteMany();
  await prisma.courierRequest.deleteMany();
  await prisma.driverSubscription.deleteMany();
  await prisma.supportTicket.deleteMany();
  await prisma.rentalListing.deleteMany();
  await prisma.carPaddyRequest.deleteMany();
  await prisma.driverDocument.deleteMany();
  await prisma.trip.deleteMany();
  await prisma.vehicle.deleteMany();
  await prisma.driver.deleteMany();
  await prisma.user.deleteMany();
}
