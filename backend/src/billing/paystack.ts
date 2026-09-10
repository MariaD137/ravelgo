import { createHmac, timingSafeEqual } from "node:crypto";
import { env } from "../config/env";

// A dummy key lets requests be constructed successfully in dev/test where no
// real Paystack account is configured — only an actual network call fails.
// Tests mock paystackClient's methods directly (see src/test/helpers.ts)
// rather than ever reaching the network, the same pattern the removed
// stripeClient singleton used.
const PAYSTACK_SECRET_KEY = env.PAYSTACK_SECRET_KEY ?? "sk_test_dummy_for_local_dev_and_tests";
const PAYSTACK_BASE_URL = "https://api.paystack.co";

export class PaystackApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "PaystackApiError";
  }
}

/**
 * Every Paystack REST response is `{ status: boolean, message: string, data: T }`.
 * `status` here is Paystack's own request-succeeded boolean — unrelated to,
 * and not to be confused with, an individual transaction/transfer's status
 * field inside `data` (e.g. "success" | "failed" | "pending").
 */
interface PaystackEnvelope<T> {
  status: boolean;
  message: string;
  data: T;
}

async function paystackRequest<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${PAYSTACK_BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  let parsed: PaystackEnvelope<T> | undefined;
  try {
    parsed = (await res.json()) as PaystackEnvelope<T>;
  } catch {
    // Fall through to the generic error below — parsed stays undefined.
  }

  if (!res.ok || !parsed?.status) {
    throw new PaystackApiError(parsed?.message ?? `Paystack request failed (${res.status})`, res.status);
  }
  return parsed.data;
}

export interface InitializeTransactionParams {
  email: string;
  /** Integer kobo (Naira minor unit) — same shape as lib/money.ts#toCents. */
  amountKobo: number;
  /** A reference RavelGo generates and owns, used for idempotency and later lookup/verification/refund. */
  reference: string;
  currency?: string;
  metadata?: Record<string, unknown>;
}

export interface InitializeTransactionResult {
  authorizationUrl: string;
  accessCode: string;
  reference: string;
}

export type PaystackTransactionStatus = "success" | "failed" | "abandoned" | "pending" | "reversed";

export interface VerifyTransactionResult {
  status: PaystackTransactionStatus;
  reference: string;
  amountKobo: number;
  currency: string;
  metadata: Record<string, unknown> | null;
  paidAt: string | null;
}

export interface RefundParams {
  reference: string;
  /** Omit for a full refund. Integer kobo for a partial refund. */
  amountKobo?: number;
}

export interface ResolvedAccount {
  accountNumber: string;
  accountName: string;
}

export interface BankListing {
  name: string;
  code: string;
}

export interface CreateTransferRecipientParams {
  name: string;
  accountNumber: string;
  bankCode: string;
}

export interface InitiateTransferParams {
  /** Integer kobo. */
  amountKobo: number;
  recipientCode: string;
  /** A reference RavelGo generates and owns — used to match the later transfer.success/transfer.failed webhook back to the right Payout. */
  reference: string;
  reason?: string;
}

export type PaystackTransferStatus = "pending" | "success" | "failed" | "reversed" | "otp";

/**
 * The single Paystack integration point (Phase 12: "a dedicated
 * service/module such as PaystackService... Follow the existing RavelGo
 * coding patterns") — mirrors the shape of the removed stripeClient/the
 * existing cognitoGroups singleton so tests can mock individual methods with
 * the same `mock.method(paystackClient, "initializeTransaction", ...)`
 * pattern already used everywhere else (src/test/helpers.ts).
 */
export const paystackClient = {
  /** POST /transaction/initialize — starts a card/bank charge. */
  async initializeTransaction(params: InitializeTransactionParams): Promise<InitializeTransactionResult> {
    const data = await paystackRequest<{ authorization_url: string; access_code: string; reference: string }>(
      "POST",
      "/transaction/initialize",
      {
        email: params.email,
        amount: params.amountKobo,
        currency: params.currency ?? "NGN",
        reference: params.reference,
        metadata: params.metadata,
      },
    );
    return { authorizationUrl: data.authorization_url, accessCode: data.access_code, reference: data.reference };
  },

  /**
   * GET /transaction/verify/:reference — the trusted source of truth for a
   * transaction's real outcome. The webhook handler calls this before
   * fulfilling ANY charge.success event rather than trusting the webhook
   * payload alone (Paystack's own recommended pattern), so a forged or
   * malformed webhook body can never fulfil an order on its own.
   */
  async verifyTransaction(reference: string): Promise<VerifyTransactionResult> {
    const data = await paystackRequest<{
      status: PaystackTransactionStatus;
      reference: string;
      amount: number;
      currency: string;
      metadata: Record<string, unknown> | string | null;
      paid_at: string | null;
    }>("GET", `/transaction/verify/${encodeURIComponent(reference)}`);
    // Paystack returns metadata as "" (empty string) rather than null when
    // none was set on initialize, instead of a JSON object — normalize it.
    const metadata = data.metadata && typeof data.metadata === "object" ? data.metadata : null;
    return {
      status: data.status,
      reference: data.reference,
      amountKobo: data.amount,
      currency: data.currency,
      metadata,
      paidAt: data.paid_at,
    };
  },

  /** POST /refund. */
  async refundTransaction(params: RefundParams): Promise<{ status: string }> {
    const data = await paystackRequest<{ status: string }>("POST", "/refund", {
      transaction: params.reference,
      amount: params.amountKobo,
    });
    return { status: data.status };
  },

  /**
   * GET /bank/resolve — confirms an account number is real and returns the
   * bank's name for it, BEFORE a transfer recipient is ever created.
   * Paystack itself requires this: creating a recipient against an
   * unresolved account number fails.
   */
  async resolveAccountNumber(accountNumber: string, bankCode: string): Promise<ResolvedAccount> {
    const data = await paystackRequest<{ account_number: string; account_name: string }>(
      "GET",
      `/bank/resolve?account_number=${encodeURIComponent(accountNumber)}&bank_code=${encodeURIComponent(bankCode)}`,
    );
    return { accountNumber: data.account_number, accountName: data.account_name };
  },

  /** GET /bank — the list of Nigerian banks + their Paystack bank codes, for the driver bank-account form. */
  async listBanks(): Promise<BankListing[]> {
    const data = await paystackRequest<Array<{ name: string; code: string }>>(
      "GET",
      "/bank?country=nigeria&currency=NGN",
    );
    return data.map((b) => ({ name: b.name, code: b.code }));
  },

  /**
   * POST /transferrecipient — creates (or, from Paystack's perspective,
   * re-creates; RavelGo caches the resulting code so this is only called
   * once per driver bank account, see payouts.ts) a payout destination.
   */
  async createTransferRecipient(params: CreateTransferRecipientParams): Promise<{ recipientCode: string }> {
    const data = await paystackRequest<{ recipient_code: string }>("POST", "/transferrecipient", {
      type: "nuban",
      name: params.name,
      account_number: params.accountNumber,
      bank_code: params.bankCode,
      currency: "NGN",
    });
    return { recipientCode: data.recipient_code };
  },

  /** POST /transfer — moves money from RavelGo's Paystack balance to a driver's bank account. */
  async initiateTransfer(params: InitiateTransferParams): Promise<{ transferCode: string; status: PaystackTransferStatus }> {
    const data = await paystackRequest<{ transfer_code: string; status: PaystackTransferStatus }>("POST", "/transfer", {
      source: "balance",
      amount: params.amountKobo,
      recipient: params.recipientCode,
      reference: params.reference,
      reason: params.reason,
    });
    return { transferCode: data.transfer_code, status: data.status };
  },
};

/**
 * Verify the `x-paystack-signature` header: HMAC-SHA512 of the exact raw
 * request body, keyed with the secret key (Paystack has no separate
 * webhook-signing secret, unlike Stripe). Constant-time comparison so this
 * can never be timed to leak the expected signature. A free function, not
 * part of paystackClient — it does no network I/O, so tests exercise it for
 * real (see billing.routes.test.ts building a real signature) rather than
 * mocking it.
 */
export function verifyWebhookSignature(rawBody: Buffer, signature: string | undefined): boolean {
  if (!signature) return false;
  const expected = signWebhookPayloadForTesting(rawBody);
  const expectedBuf = Buffer.from(expected, "utf8");
  const actualBuf = Buffer.from(signature, "utf8");
  if (expectedBuf.length !== actualBuf.length) return false;
  return timingSafeEqual(expectedBuf, actualBuf);
}

/**
 * Computes the same signature verifyWebhookSignature() checks for — exported
 * so tests can build a real, validly-signed webhook request (the same role
 * Stripe's own stripeClient.webhooks.generateTestHeaderString() played for
 * the removed Stripe integration) without duplicating the HMAC/secret
 * details in test code.
 */
export function signWebhookPayloadForTesting(rawBody: Buffer): string {
  return createHmac("sha512", PAYSTACK_SECRET_KEY).update(rawBody).digest("hex");
}
