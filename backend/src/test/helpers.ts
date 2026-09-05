import { mock } from "node:test";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { stripeClient } from "../billing/stripe";
import { cognitoGroups } from "../services/cognito";

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

/**
 * Like mockAuthAs but recognizes SEVERAL identities at once, so a test can fire
 * concurrent requests as different users (each `mock.method` call replaces the
 * previous stub, so calling mockAuthAs twice would leave only the last user
 * authenticatable). Returns a map of sub -> bearer token.
 */
export function mockAuthAsMany(users: MockCognitoUser[]): Record<string, string> {
  const bySub = new Map(users.map((u) => [`mock.${u.sub}`, u]));
  mock.method(verifier, "verify", async (candidate: string) => {
    const user = bySub.get(candidate);
    if (!user) throw new Error("invalid token");
    return { sub: user.sub, email: user.email, "cognito:groups": user.groups ?? [] } as never;
  });
  return Object.fromEntries(users.map((u) => [u.sub, `mock.${u.sub}`]));
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

/**
 * Stubs cognitoGroups.addUserToGroup so route tests exercising the
 * server-authoritative role grant never call a real Cognito user pool. Returns
 * the mock so a test can assert it was called with the expected sub/group.
 * Pass `shouldThrow` to simulate Cognito rejecting the group add.
 */
export function mockCognitoAddToGroup({ shouldThrow = false } = {}) {
  return mock.method(cognitoGroups, "addUserToGroup", async () => {
    if (shouldThrow) throw new Error("simulated Cognito failure");
  });
}

/**
 * Stubs cognitoGroups.createAdminUser so admin-user-invite tests never call a
 * real Cognito user pool. Returns the mock so a test can inspect call args;
 * the stubbed username defaults to a synthetic value distinct from the real
 * email, catching any code that wrongly assumes email === Username.
 */
export function mockCognitoCreateAdminUser(username = "cognito-generated-username") {
  return mock.method(cognitoGroups, "createAdminUser", async () => ({ username }));
}

export function mockCognitoSetUserEnabled() {
  return mock.method(cognitoGroups, "setUserEnabled", async () => {});
}

// Delete in FK-safe order (children before parents).
export async function resetDb() {
  // AuditLog has no FK dependents; clear it too so audit-writing admin routes
  // in one test don't leak entries into another (the audit test asserts an
  // exact row count).
  await prisma.auditLog.deleteMany();
  // Payout and WalletAccount are ON DELETE RESTRICT against User (P0 #12), so
  // they must be cleared explicitly before users (they no longer cascade).
  await prisma.payout.deleteMany();
  await prisma.driverBankAccount.deleteMany();
  await prisma.foodOrderItem.deleteMany();
  await prisma.foodOrder.deleteMany();
  await prisma.menuItem.deleteMany();
  await prisma.restaurant.deleteMany();
  await prisma.walletTransaction.deleteMany();
  await prisma.walletAccount.deleteMany();
  await prisma.payment.deleteMany();
  await prisma.emergencyAlert.deleteMany();
  await prisma.courierRequest.deleteMany();
  await prisma.driverSubscription.deleteMany();
  await prisma.supportTicket.deleteMany();
  // RentalBooking -> RentalListing is ON DELETE RESTRICT, so bookings must
  // go first.
  await prisma.rentalBooking.deleteMany();
  await prisma.rentalListing.deleteMany();
  // StayBooking -> PropertyListing is ON DELETE RESTRICT, so bookings must
  // go first.
  await prisma.stayBooking.deleteMany();
  await prisma.propertyListing.deleteMany();
  await prisma.carPaddyRequest.deleteMany();
  await prisma.driverDocument.deleteMany();
  await prisma.trip.deleteMany();
  await prisma.vehicle.deleteMany();
  await prisma.driver.deleteMany();
  await prisma.user.deleteMany();
}
