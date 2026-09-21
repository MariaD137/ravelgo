import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireActiveAdmin } from "../lib/admin-permissions";

export const loyaltyRouter = Router();

// Any authenticated user: browse the tier ladder
loyaltyRouter.get("/loyalty-tiers", requireAuth, async (_req, res) => {
  const tiers = await prisma.loyaltyTier.findMany({ orderBy: { minCompletedTrips: "asc" } });
  res.json(tiers);
});

const createTierSchema = z.object({
  name: z.string().min(1),
  minCompletedTrips: z.number().int().nonnegative(),
  discountPercent: z.number().min(0).max(100),
  perks: z.string().optional(),
});

// Admin: define a tier
loyaltyRouter.post("/loyalty-tiers", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = createTierSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const tier = await prisma.loyaltyTier.create({ data: parsed.data });
  res.status(201).json(tier);
});

// Rider: my current tier, computed from completed trips (not stored, so it
// can never drift out of sync with actual ride history)
loyaltyRouter.get("/riders/me/loyalty", requireAuth, requireRole("Rider"), async (req, res) => {
  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!rider) return res.status(404).json({ error: "Rider profile not found" });

  const completedTrips = await prisma.trip.count({ where: { riderId: rider.id, status: "COMPLETED" } });

  const tiers = await prisma.loyaltyTier.findMany({ orderBy: { minCompletedTrips: "desc" } });
  const currentTier = tiers.find((tier) => completedTrips >= tier.minCompletedTrips) ?? null;

  res.json({ completedTrips, currentTier });
});

// Any authenticated user: browse redeemable promotions
loyaltyRouter.get("/promotions", requireAuth, async (_req, res) => {
  const promotions = await prisma.promotion.findMany({
    where: { active: true, OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
    orderBy: { createdAt: "desc" },
  });
  res.json(promotions);
});

const createPromotionSchema = z.object({
  code: z.string().min(1),
  description: z.string().min(1),
  discountPercent: z.number().min(0).max(100),
  expiresAt: z.coerce.date().optional(),
  maxRedemptions: z.number().int().positive().optional(),
});

// Admin: create a promotion code
loyaltyRouter.post("/promotions", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = createPromotionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const promotion = await prisma.promotion.create({ data: parsed.data });
  res.status(201).json(promotion);
});

// Any authenticated user: redeem a promotion code, once
loyaltyRouter.post("/promotions/:code/redeem", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const promotion = await prisma.promotion.findUnique({ where: { code: req.params.code } });
  if (!promotion || !promotion.active) return res.status(404).json({ error: "Promotion not found" });
  if (promotion.expiresAt && promotion.expiresAt < new Date()) {
    return res.status(409).json({ error: "Promotion has expired" });
  }
  if (promotion.maxRedemptions != null && promotion.redemptionCount >= promotion.maxRedemptions) {
    return res.status(409).json({ error: "Promotion has reached its redemption limit" });
  }

  const alreadyRedeemed = await prisma.promotionRedemption.findUnique({
    where: { promotionId_userId: { promotionId: promotion.id, userId: user.id } },
  });
  if (alreadyRedeemed) return res.status(409).json({ error: "You've already redeemed this promotion" });

  const [redemption] = await prisma.$transaction([
    prisma.promotionRedemption.create({ data: { promotionId: promotion.id, userId: user.id } }),
    prisma.promotion.update({ where: { id: promotion.id }, data: { redemptionCount: { increment: 1 } } }),
  ]);
  res.status(201).json({ redemption, discountPercent: promotion.discountPercent });
});
