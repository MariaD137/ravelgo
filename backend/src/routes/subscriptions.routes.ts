import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";

export const subscriptionsRouter = Router();

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

// Any authenticated user: browse active subscription plans
subscriptionsRouter.get("/subscription-plans", requireAuth, async (_req, res) => {
  const plans = await prisma.subscriptionPlan.findMany({ where: { active: true } });
  res.json(plans);
});

const createPlanSchema = z.object({
  name: z.string().min(1),
  description: z.string().min(1),
  priceMonthly: z.number().positive(),
});

// Admin (Super Admin / Operations Manager): create a new subscription plan
subscriptionsRouter.post("/subscription-plans", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = createPlanSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const plan = await prisma.subscriptionPlan.create({ data: parsed.data });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "SUBSCRIPTION_PLAN_CREATED",
    entityType: "SubscriptionPlan",
    entityId: plan.id,
    metadata: { name: plan.name, priceMonthly: plan.priceMonthly },
  });
  res.status(201).json(plan);
});

const subscribeSchema = z.object({
  planId: z.string().min(1),
});

// Every SubscriptionPlan is priced `priceMonthly` — a fixed 30-day billing
// cycle for every plan today. Computed here, never accepted from the client:
// a caller-supplied currentPeriodEnd would let a driver simply assert their
// own (arbitrarily distant) renewal date with nothing to actually back it.
const SUBSCRIPTION_PERIOD_DAYS = 30;

// Driver: subscribe (or switch) to a plan.
//
// KNOWN GAP (not fixed here — this route's job is wiring/validation, not
// billing): this does not charge the driver anything, and Driver.subscriptionActive
// is not read anywhere in services/commission.ts or pricing.ts — subscribing
// currently has no effect on the commission a driver actually pays, despite
// SubscriptionPlan.description marketing lower fees. A real implementation
// needs a Paystack charge (like wallet top-ups; see billing/paystack.ts)
// gating activation, a renewal/expiry sweep (like services/matching.ts's
// startOfferExpirySweep), and resolveCommissionRate() actually reading
// subscriptionActive. Flagged rather than silently building a fake discount.
subscriptionsRouter.post("/drivers/me/subscription", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = subscribeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const plan = await prisma.subscriptionPlan.findUnique({ where: { id: parsed.data.planId } });
  if (!plan || !plan.active) return res.status(404).json({ error: "Plan not found" });

  const currentPeriodEnd = new Date(Date.now() + SUBSCRIPTION_PERIOD_DAYS * 86400000);
  const subscription = await prisma.driverSubscription.upsert({
    where: { driverId: driver.id },
    update: {
      planId: plan.id,
      status: "ACTIVE",
      startedAt: new Date(),
      currentPeriodEnd,
    },
    create: {
      driverId: driver.id,
      planId: plan.id,
      currentPeriodEnd,
    },
  });
  await prisma.driver.update({ where: { id: driver.id }, data: { subscriptionActive: true } });

  res.status(201).json(subscription);
});

// Driver: view my own subscription
subscriptionsRouter.get("/drivers/me/subscription", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const subscription = await prisma.driverSubscription.findUnique({
    where: { driverId: driver.id },
    include: { plan: true },
  });
  if (!subscription) return res.status(404).json({ error: "No active subscription" });
  res.json(subscription);
});

// Driver: cancel my own subscription
subscriptionsRouter.delete("/drivers/me/subscription", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const subscription = await prisma.driverSubscription.findUnique({ where: { driverId: driver.id } });
  if (!subscription) return res.status(404).json({ error: "No active subscription" });

  const updated = await prisma.driverSubscription.update({
    where: { driverId: driver.id },
    data: { status: "CANCELLED" },
  });
  await prisma.driver.update({ where: { id: driver.id }, data: { subscriptionActive: false } });

  res.json(updated);
});
