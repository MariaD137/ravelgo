import Stripe from "stripe";
import { env } from "../config/env";

// A dummy key lets the SDK construct successfully in dev/test where no real
// Stripe account is configured — the constructor itself never validates a
// key against Stripe's API, only an actual call does. Tests mock the calls
// directly (see mockPaymentIntentCreate() in src/test/helpers.ts) rather
// than ever reaching the network, the same pattern used for the Cognito
// verifier in src/middleware/auth.ts.
export const stripeClient = new Stripe(env.STRIPE_SECRET_KEY ?? "sk_test_dummy_for_local_dev_and_tests");
