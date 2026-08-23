import { Router } from "express";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";

export const loyaltyRouter = Router();

class PromotionLimitReachedError extends Error {}

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

  const promotion = await prisma.promotion.findUnique({ where: { code: req.params.code } });
  if (!promotion || !promotion.active) return res.status(404).json({ error: "Promotion not found" });
  if (promotion.expiresAt && promotion.expiresAt < new Date()) {
    return res.status(409).json({ error: "Promotion has expired" });
  }

  // Both checks below are pre-checks for a fast, clean error in the common
  // case — the real guarantee comes from the transaction: an atomic
  // conditional updateMany (maxRedemptions) and the promotionId_userId
  // unique constraint (double-redeem) each close a race two concurrent
  // requests could otherwise both pass this early read-then-write check
  // before either commits.
  if (promotion.maxRedemptions != null && promotion.redemptionCount >= promotion.maxRedemptions) {
    return res.status(409).json({ error: "Promotion has reached its redemption limit" });
  }
  const alreadyRedeemed = await prisma.promotionRedemption.findUnique({
    where: { promotionId_userId: { promotionId: promotion.id, userId: user.id } },
  });
  if (alreadyRedeemed) return res.status(409).json({ error: "You've already redeemed this promotion" });

  try {
    const redemption = await prisma.$transaction(async (tx) => {
      if (promotion.maxRedemptions != null) {
        // The "still under the limit" check and the increment happen in one
        // statement, so two different users redeeming near the limit at the
        // same time can't both pass a read-then-write check before either
        // commits — same conditional-updateMany pattern used for every
        // other state machine in this codebase.
        const { count } = await tx.promotion.updateMany({
          where: { id: promotion.id, redemptionCount: { lt: promotion.maxRedemptions } },
          data: { redemptionCount: { increment: 1 } },
        });
        if (count === 0) throw new PromotionLimitReachedError();
      } else {
        await tx.promotion.update({ where: { id: promotion.id }, data: { redemptionCount: { increment: 1 } } });
      }
      return tx.promotionRedemption.create({ data: { promotionId: promotion.id, userId: user.id } });
    });
    res.status(201).json({ redemption, discountPercent: promotion.discountPercent });
  } catch (err) {
    if (err instanceof PromotionLimitReachedError) {
      return res.status(409).json({ error: "Promotion has reached its redemption limit" });
    }
    // promotionId_userId is @unique — the loser of a race that both passed
    // the `alreadyRedeemed` check above lands here instead of an unhandled
    // 500 (same pattern as payments.routes.ts's charge-race handling).
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
      return res.status(409).json({ error: "You've already redeemed this promotion" });
    }
    throw err;
  }
});
