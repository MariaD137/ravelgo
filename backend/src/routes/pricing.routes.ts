import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { computeFare, findActiveSurgeZone, requireActivePricingRule } from "../services/pricing";

export const pricingRouter = Router();

// Any authenticated user: browse pricing rules (the app needs these to show
// an estimate before requesting a trip)
pricingRouter.get("/pricing-rules", requireAuth, async (_req, res) => {
  const rules = await prisma.pricingRule.findMany({ orderBy: { createdAt: "desc" } });
  res.json(rules);
});

const createPricingRuleSchema = z.object({
  name: z.string().min(1),
  baseFare: z.number().nonnegative(),
  perKm: z.number().nonnegative(),
  perMinute: z.number().nonnegative(),
});

// Admin: define a pricing rule
pricingRouter.post("/pricing-rules", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = createPricingRuleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rule = await prisma.pricingRule.create({ data: parsed.data });
  res.status(201).json(rule);
});

const updatePricingRuleSchema = createPricingRuleSchema.partial().extend({
  active: z.boolean().optional(),
});

// Admin: update or (de)activate a pricing rule
pricingRouter.patch("/pricing-rules/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = updatePricingRuleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rule = await prisma.pricingRule.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(rule);
});

// Any authenticated user: browse surge zones
pricingRouter.get("/surge-zones", requireAuth, async (_req, res) => {
  const zones = await prisma.surgeZone.findMany({ orderBy: { createdAt: "desc" } });
  res.json(zones);
});

const createSurgeZoneSchema = z.object({
  name: z.string().min(1),
  location: z.string().min(1),
  multiplier: z.number().positive(),
  startsAt: z.coerce.date().optional(),
  endsAt: z.coerce.date().optional(),
});

// Admin: define a surge zone
pricingRouter.post("/surge-zones", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = createSurgeZoneSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const zone = await prisma.surgeZone.create({ data: parsed.data });
  res.status(201).json(zone);
});

const updateSurgeZoneSchema = createSurgeZoneSchema.partial().extend({
  active: z.boolean().optional(),
});

// Admin: update or (de)activate a surge zone
pricingRouter.patch("/surge-zones/:id", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = updateSurgeZoneSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const zone = await prisma.surgeZone.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(zone);
});

const quoteSchema = z.object({
  distanceKm: z.coerce.number().nonnegative(),
  durationMinutes: z.coerce.number().nonnegative(),
  zone: z.string().optional(),
});

// Any authenticated user: get a fare estimate before requesting a trip.
// Uses whichever PricingRule is currently active (there should only be one —
// enforced by convention, not a DB constraint) and, if `zone` matches an
// active SurgeZone by name, multiplies the result.
pricingRouter.get("/pricing/quote", requireAuth, async (req, res) => {
  const parsed = quoteSchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { distanceKm, durationMinutes, zone } = parsed.data;

  // No active rule -> the same 409 as before, surfaced from the shared helper.
  let rule;
  try {
    rule = await requireActivePricingRule();
  } catch {
    return res.status(409).json({ error: "No active pricing rule configured" });
  }
  const surge = await findActiveSurgeZone(zone);
  res.json(computeFare(rule, distanceKm, durationMinutes, surge));
});
