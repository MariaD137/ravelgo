import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { calculateFinalFare, NoPricingRuleError } from "./fare";

beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("calculateFinalFare uses the active PricingRule's formula, not any client-supplied amount", async () => {
  await prisma.pricingRule.create({ data: { name: "Standard", baseFare: 3, perKm: 2, perMinute: 0.5, active: true } });
  const fare = await calculateFinalFare(5, 10);
  // 3 + 2*5 + 0.5*10 = 18 — calculateFinalFare's signature doesn't even
  // accept a dollar amount, only distance/duration; there is no code path
  // through which a caller can pass a fare directly.
  assert.equal(fare, 18);
});

test("calculateFinalFare ignores an inactive PricingRule and uses the active one", async () => {
  await prisma.pricingRule.create({ data: { name: "Old", baseFare: 100, perKm: 100, perMinute: 100, active: false } });
  await prisma.pricingRule.create({ data: { name: "Current", baseFare: 1, perKm: 1, perMinute: 1, active: true } });
  const fare = await calculateFinalFare(2, 2);
  assert.equal(fare, 1 + 1 * 2 + 1 * 2); // 5, not the inactive rule's numbers
});

test("calculateFinalFare throws when no PricingRule is active, instead of silently defaulting", async () => {
  await assert.rejects(() => calculateFinalFare(5, 5), NoPricingRuleError);
});

test("calculateFinalFare rounds to the cent", async () => {
  await prisma.pricingRule.create({ data: { name: "Fractional", baseFare: 1, perKm: 0.333, perMinute: 0, active: true } });
  const fare = await calculateFinalFare(1, 0);
  assert.equal(fare, 1.33);
});
