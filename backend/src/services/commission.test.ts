import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import {
  DEFAULT_COMMISSION_RATE,
  getServiceCommissionRate,
  resolveCommissionRate,
  setServiceCommissionRate,
  splitCommission,
} from "./commission";

beforeEach(resetDb);
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

// The two examples straight from the pricing spec.
test("splitCommission: a ₦5,000 ride at 20% -> RavelGo ₦1,000, driver ₦4,000", () => {
  const split = splitCommission(5000, 0.2);
  assert.equal(split.commissionRate, 0.2);
  assert.equal(split.commissionAmount, 1000);
  assert.equal(split.driverEarnings, 4000);
  assert.equal(split.commissionAmount + split.driverEarnings, 5000);
});

test("splitCommission: a ₦10,000 delivery at 20% -> RavelGo ₦2,000, driver ₦8,000", () => {
  const split = splitCommission(10000, 0.2);
  assert.equal(split.commissionAmount, 2000);
  assert.equal(split.driverEarnings, 8000);
  assert.equal(split.commissionAmount + split.driverEarnings, 10000);
});

test("splitCommission never leaks a cent — commission + driverEarnings always equals the gross, for odd amounts", () => {
  for (const gross of [1, 3, 7, 99.99, 12345.67, 1000.01]) {
    for (const rate of [0.05, 0.1, 0.2, 0.33, 0.5]) {
      const split = splitCommission(gross, rate);
      const grossCents = Math.round(gross * 100);
      const commissionCents = Math.round(split.commissionAmount * 100);
      const driverCents = Math.round(split.driverEarnings * 100);
      assert.equal(commissionCents + driverCents, grossCents, `gross=${gross} rate=${rate}`);
    }
  }
});

test("splitCommission rejects a negative or out-of-range rate", () => {
  assert.throws(() => splitCommission(1000, -0.1));
  assert.throws(() => splitCommission(1000, 1.1));
});

test("splitCommission rejects a negative gross amount", () => {
  assert.throws(() => splitCommission(-1, 0.2));
});

test("getServiceCommissionRate seeds the platform default (20%) on first read", async () => {
  const rate = await getServiceCommissionRate("RIDE");
  assert.equal(rate, DEFAULT_COMMISSION_RATE);
  assert.equal(rate, 0.2);
});

test("setServiceCommissionRate persists Admin's configured rate; subsequent reads see it, not the default", async () => {
  await setServiceCommissionRate("DELIVERY", 0.18, "admin@example.com");
  const rate = await getServiceCommissionRate("DELIVERY");
  assert.equal(rate, 0.18);
});

test("setServiceCommissionRate rejects an out-of-range rate", async () => {
  await assert.rejects(() => setServiceCommissionRate("RIDE", 1.5, "admin@example.com"));
  await assert.rejects(() => setServiceCommissionRate("RIDE", -0.1, "admin@example.com"));
});

test("resolveCommissionRate: a category/vehicle-class override wins over the service default", async () => {
  await setServiceCommissionRate("RIDE", 0.2, "admin@example.com");
  const overridden = await resolveCommissionRate("RIDE", 0.15);
  assert.equal(overridden, 0.15);
  const notOverridden = await resolveCommissionRate("RIDE", null);
  assert.equal(notOverridden, 0.2);
});
