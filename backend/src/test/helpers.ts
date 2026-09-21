import { mock } from "node:test";
import { verifier } from "../middleware/auth";
import { prisma } from "../db/prisma";
import { paystackClient, type PaystackTransactionStatus } from "../billing/paystack";
import { cognitoGroups } from "../services/cognito";
import { resetDriverLocationThrottle } from "../services/driver-location";
import { resetMatchingThrottle } from "../services/matching";

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
 * Stubs paystackClient.initializeTransaction so route tests never make a
 * real network call to Paystack — returns a fake authorizationUrl carrying
 * whatever reference the route itself generated (RavelGo owns the
 * reference, unlike Stripe's server-generated PaymentIntent id — see
 * billing/paystack.ts), same pattern as mockAuthAs() for the Cognito verifier.
 */
export function mockPaystackInitialize() {
  return mock.method(paystackClient, "initializeTransaction", async ({ reference }: { reference: string }) => ({
    authorizationUrl: `https://checkout.paystack.com/test_${reference}`,
    accessCode: `access_test_${reference}`,
    reference,
  }));
}

/**
 * Stubs paystackClient.verifyTransaction — the webhook handler's trusted
 * source of truth for a transaction's real outcome AND the metadata that
 * decides which branch handles it (billing.routes.ts reads type from the
 * VERIFY response, never the raw webhook payload — see its comment on why).
 * Defaults to a bare "success" with no metadata (the "trip" branch); pass
 * `metadata` to simulate a wallet_topup/courier_delivery/rental_booking
 * transaction, or a different `status` to simulate a failed verification.
 */
export function mockPaystackVerify({
  status = "success" as PaystackTransactionStatus,
  metadata = null as Record<string, unknown> | null,
} = {}) {
  return mock.method(paystackClient, "verifyTransaction", async (reference: string) => ({
    status,
    reference,
    amountKobo: 0,
    currency: "NGN",
    metadata,
    paidAt: status === "success" ? new Date().toISOString() : null,
  }));
}

/** Stubs paystackClient.refundTransaction so refund tests never hit the network. */
export function mockPaystackRefund() {
  return mock.method(paystackClient, "refundTransaction", async () => ({ status: "success" }));
}

/** Stubs the driver-payout Paystack Transfer flow (resolve + recipient + transfer). */
export function mockPaystackTransfer() {
  mock.method(paystackClient, "resolveAccountNumber", async (accountNumber: string) => ({
    accountNumber,
    accountName: "Test Driver",
  }));
  mock.method(paystackClient, "createTransferRecipient", async () => ({ recipientCode: "RCP_test_1" }));
  mock.method(paystackClient, "initiateTransfer", async () => ({ transferCode: "TRF_test_1", status: "pending" as const }));
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

/**
 * Stubs cognitoGroups.adminUserStatus so admin-user route tests never call a
 * real Cognito user pool. Defaults to an active, MFA-enabled account so tests
 * that don't care about status/MFA see the "normal" case; override either
 * field, or pass null to simulate the Cognito account not existing.
 */
export function mockCognitoAdminUserStatus(
  result: { cognitoStatus?: string; mfaEnabled?: boolean } | null = {},
) {
  return mock.method(cognitoGroups, "adminUserStatus", async () =>
    result === null ? null : { cognitoStatus: result.cognitoStatus ?? "CONFIRMED", mfaEnabled: result.mfaEnabled ?? false },
  );
}

export function mockCognitoResendAdminInvitation() {
  return mock.method(cognitoGroups, "resendAdminInvitation", async () => {});
}

export function mockCognitoAdminResetUserPassword() {
  return mock.method(cognitoGroups, "adminResetUserPassword", async () => {});
}

/**
 * Driver row fields placing a driver at a fresh (or `ageMs`-old) reported
 * position — trip matching (services/matching.ts) only offers rides to
 * drivers with a recent location, so any test expecting an OFFER needs this.
 */
export function locatedAt(lat: number, lng: number, ageMs = 0) {
  return { lastLat: lat, lastLng: lng, lastLocationAt: new Date(Date.now() - ageMs) };
}

// Delete in FK-safe order (children before parents).
export async function resetDb() {
  resetDriverLocationThrottle();
  resetMatchingThrottle();
  // AuditLog has no FK dependents; clear it too so audit-writing admin routes
  // in one test don't leak entries into another (the audit test asserts an
  // exact row count).
  await prisma.auditLog.deleteMany();
  // FinancialTransaction is deliberately NOT a Prisma relation to
  // Trip/CourierRequest/Payment/Driver/User (an append-only ledger must
  // survive even if the entity it references is later deleted) — no FK
  // ordering constraint, safe to clear anywhere, same as AuditLog above.
  await prisma.financialTransaction.deleteMany();
  await prisma.rideCategory.deleteMany();
  await prisma.deliveryVehicleRate.deleteMany();
  await prisma.commissionConfig.deleteMany();
  await prisma.pricingPolicy.deleteMany();
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
  await prisma.notification.deleteMany();
  await prisma.pushToken.deleteMany();
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
  // CashRemittance -> Driver is ON DELETE RESTRICT, so remittances must go first.
  await prisma.cashRemittance.deleteMany();
  await prisma.vehicle.deleteMany();
  await prisma.driver.deleteMany();
  // Referral cascades from User at the database level, but clearing it
  // explicitly keeps the intent obvious and the ordering independent of that.
  await prisma.referral.deleteMany();
  await prisma.user.deleteMany();
  // Global singleton config, not user-scoped, but reset so one test's cash
  // limit/enabled-method change can never leak into another.
  await prisma.appSetting.deleteMany();
}
