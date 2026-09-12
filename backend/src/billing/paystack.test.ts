import assert from "node:assert/strict";
import { test } from "node:test";
import { PaystackApiError, evaluatePaystackKey, paystackClient, paystackConfig } from "./paystack";

test("evaluatePaystackKey: unset, placeholder and malformed keys are reported as unconfigured", () => {
  assert.deepEqual(evaluatePaystackKey(undefined), { configured: false, reason: "unset" });
  assert.deepEqual(evaluatePaystackKey("   "), { configured: false, reason: "unset" });
  // The literal value infra/lib/api-stack.ts seeds into Secrets Manager.
  assert.deepEqual(evaluatePaystackKey("sk_live_REPLACE_ME"), { configured: false, reason: "placeholder" });
  assert.deepEqual(evaluatePaystackKey("sk_test_dummy_for_local_dev_and_tests"), {
    configured: false,
    reason: "placeholder",
  });
  // A public key, or any non-secret-key string, can never authenticate.
  assert.deepEqual(evaluatePaystackKey("pk_test_abc123"), { configured: false, reason: "malformed" });
  assert.deepEqual(evaluatePaystackKey("not a key"), { configured: false, reason: "malformed" });
});

test("evaluatePaystackKey: real-looking test and live keys are configured with their mode", () => {
  assert.deepEqual(evaluatePaystackKey("sk_test_0123456789abcdefABCDEF"), { configured: true, mode: "test" });
  assert.deepEqual(evaluatePaystackKey(" sk_live_0123456789abcdefABCDEF "), { configured: true, mode: "live" });
});

test("an unconfigured key makes every Paystack call fail fast with a 503 PaystackApiError, without any network call", async () => {
  // The test environment never sets PAYSTACK_SECRET_KEY, so this exercises
  // the same guard a mis-deployed staging service hits.
  assert.equal(paystackConfig.configured, false);
  await assert.rejects(
    () => paystackClient.listBanks(),
    (err: unknown) => {
      assert.ok(err instanceof PaystackApiError);
      assert.equal(err.status, 503);
      assert.match(err.message, /PAYSTACK_SECRET_KEY is unset/);
      // The message tells an operator what to do, and never echoes a key.
      assert.match(err.message, /Secrets Manager/);
      assert.doesNotMatch(err.message, /sk_(test|live)_/);
      return true;
    },
  );
});
