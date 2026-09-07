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
  currentPeriodEnd: z.coerce.date(),
});

// Driver: subscribe (or switch) to a plan
subscriptionsRouter.post("/drivers/me/subscription", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = subscribeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const plan = await prisma.subscriptionPlan.findUnique({ where: { id: parsed.data.planId } });
  if (!plan || !plan.active) return res.status(404).json({ error: "Plan not found" });

  const subscription = await prisma.driverSubscription.upsert({
    where: { driverId: driver.id },
    update: {
      planId: plan.id,
      status: "ACTIVE",
      startedAt: new Date(),
      currentPeriodEnd: parsed.data.currentPeriodEnd,
    },
    create: {
      driverId: driver.id,
      planId: plan.id,
      currentPeriodEnd: parsed.data.currentPeriodEnd,
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
