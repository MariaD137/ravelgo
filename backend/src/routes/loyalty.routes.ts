import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

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
loyaltyRouter.post("/loyalty-tiers", requireAuth, requireRole("Admin"), async (req, res) => {
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
loyaltyRouter.post("/promotions", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = createPromotionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const promotion = await prisma.promotion.create({ data: parsed.data });
  res.status(201).json(promotion);
});

// Any authenticated user: redeem a promotion code, once
loyaltyRouter.post("/promotions/:code/redeem", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const result = await prisma.$transaction(async (tx) => {
    const promotion = await tx.promotion.findUnique({ where: { code: req.params.code } });
    if (!promotion || !promotion.active) return { error: "Promotion not found", status: 404 };
    if (promotion.expiresAt && promotion.expiresAt < new Date()) {
      return { error: "Promotion has expired", status: 409 };
    }
    if (promotion.maxRedemptions != null && promotion.redemptionCount >= promotion.maxRedemptions) {
      return { error: "Promotion has reached its redemption limit", status: 409 };
    }

    const alreadyRedeemed = await tx.promotionRedemption.findUnique({
      where: { promotionId_userId: { promotionId: promotion.id, userId: user.id } },
    });
    if (alreadyRedeemed) return { error: "You've already redeemed this promotion", status: 409 };

    const redemption = await tx.promotionRedemption.create({
      data: { promotionId: promotion.id, userId: user.id },
    });
    await tx.promotion.update({
      where: { id: promotion.id },
      data: { redemptionCount: { increment: 1 } },
    });

    return { redemption, discountPercent: promotion.discountPercent };
  });

  if ("error" in result && result.status) return res.status(result.status).json({ error: result.error });
  res.status(201).json(result);
});
