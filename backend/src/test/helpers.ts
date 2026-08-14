import { mock } from "node:test";
import { verifier } from "../middleware/auth";
import { stripeClient } from "../billing/stripe";
import { withBypass } from "../lib/rls";

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

// Delete in FK-safe order (children before parents). Payment/Payout/
// DriverBankAccount have FORCE ROW LEVEL SECURITY (see
// prisma/migrations/*_enable_rls_financial_tables), which also governs
// cascade deletes triggered from User/Driver — without bypass context this
// would fail with a row-level security violation instead of cleaning up.
export async function resetDb() {
  await withBypass(async (tx) => {
    await tx.payment.deleteMany();
    await tx.payout.deleteMany();
    await tx.driverBankAccount.deleteMany();
    await tx.emergencyAlert.deleteMany();
    await tx.courierRequest.deleteMany();
    await tx.driverSubscription.deleteMany();
    await tx.supportTicket.deleteMany();
    await tx.rentalListing.deleteMany();
    await tx.carPaddyRequest.deleteMany();
    await tx.driverDocument.deleteMany();
    await tx.trip.deleteMany();
    await tx.vehicle.deleteMany();
    await tx.driver.deleteMany();
    await tx.user.deleteMany();
  });
}
