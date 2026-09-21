import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { SETTINGS_ID } from "../lib/payment-rules";
import { getReferralProgram } from "../lib/referral-rules";
import { claimReferralCode, getReferralSummary, type ClaimFailure } from "../services/referral";
import { sensitiveLimiter } from "../middleware/rate-limit";

export const referralRouter = Router();

// Rider: my own referral code, the current programme terms, and how my
// invites are doing. The code is issued on first read (services/referral.ts).
referralRouter.get("/riders/me/referral", requireAuth, requireRole("Rider"), async (req, res) => {
  const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub }, select: { id: true } });
  if (!rider) return res.status(404).json({ error: "Rider profile not found" });

  res.json(await getReferralSummary(rider.id));
});

const claimSchema = z.object({ code: z.string().trim().min(1).max(32) });

/**
 * Rider: claim someone else's code.
 *
 * Rate limited like other sensitive routes: a code is a short string, and
 * without this an attacker could enumerate the space looking for a valid one
 * to attach themselves to. Every refusal reason is deliberately mapped to a
 * status the client can act on, but none of them reveal whether a code
 * exists beyond the single UNKNOWN_CODE case the user needs to see.
 */
const CLAIM_FAILURES: Record<ClaimFailure, { status: number; error: string }> = {
  PROGRAM_DISABLED: { status: 409, error: "The referral programme isn't running right now." },
  UNKNOWN_CODE: { status: 404, error: "That invite code isn't valid." },
  SELF_REFERRAL: { status: 400, error: "You can't use your own invite code." },
  ALREADY_REFERRED: { status: 409, error: "You've already used an invite code." },
  NOT_A_NEW_RIDER: { status: 409, error: "Invite codes can only be used before your first completed ride." },
};

referralRouter.post(
  "/riders/me/referral/claim",
  sensitiveLimiter,
  requireAuth,
  requireRole("Rider"),
  async (req, res) => {
    const parsed = claimSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const rider = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub }, select: { id: true } });
    if (!rider) return res.status(404).json({ error: "Rider profile not found" });

    const result = await claimReferralCode(rider.id, parsed.data.code);
    if (!result.ok) {
      const { status, error } = CLAIM_FAILURES[result.reason];
      return res.status(status).json({ error });
    }
    res.status(201).json(result.referral);
  },
);

// Admin: every referral and where it got to. Paginated like every other
// admin list (lib/pagination.ts).
const adminReferralQuerySchema = paginationQuerySchema.extend({
  status: z.enum(["PENDING", "REWARDED"]).optional(),
});

referralRouter.get("/admin/referrals", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = adminReferralQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, status } = parsed.data;

  const where = status ? { status } : {};
  const [referrals, total] = await Promise.all([
    prisma.referral.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        referrer: { select: { id: true, firstName: true, lastName: true, email: true } },
        referee: { select: { id: true, firstName: true, lastName: true, email: true } },
      },
    }),
    prisma.referral.count({ where }),
  ]);
  res.json(paginate(referrals, total, page, pageSize));
});

// Any authenticated user: the programme terms. The rider app needs these to
// describe the offer truthfully before a code is ever issued.
referralRouter.get("/settings/referral", requireAuth, async (_req, res) => {
  res.json(await getReferralProgram());
});

const updateProgramSchema = z
  .object({
    referralEnabled: z.boolean().optional(),
    referralRewardAmount: z.number().finite().min(0).max(1_000_000).optional(),
    referralRefereeRewardAmount: z.number().finite().min(0).max(1_000_000).optional(),
    referralQualifyingTrips: z.number().int().min(1).max(100).optional(),
  })
  .refine((d) => Object.keys(d).length > 0, "At least one field is required");

/**
 * Admin: configure the programme. This is the switch that starts and stops
 * real money moving, so it needs settings:write and every change is audited
 * with its old and new value, the same treatment payment settings get.
 */
referralRouter.patch(
  "/admin/settings/referral",
  requireAuth,
  requireAdminPermission("settings:write"),
  async (req, res) => {
    const parsed = updateProgramSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const before = await prisma.appSetting.upsert({
      where: { id: SETTINGS_ID },
      update: {},
      create: { id: SETTINGS_ID },
    });
    const after = await prisma.appSetting.update({ where: { id: SETTINGS_ID }, data: parsed.data });

    for (const [field, newValue] of Object.entries(parsed.data)) {
      const oldValue = (before as unknown as Record<string, unknown>)[field];
      if (oldValue !== newValue) {
        await recordAudit({
          actorSub: req.user!.sub,
          action: "REFERRAL_SETTING_CHANGED",
          entityType: "AppSetting",
          entityId: SETTINGS_ID,
          metadata: { field, oldValue, newValue },
        });
      }
    }

    res.json({
      enabled: after.referralEnabled,
      rewardAmount: after.referralRewardAmount,
      refereeRewardAmount: after.referralRefereeRewardAmount,
      qualifyingTrips: after.referralQualifyingTrips,
    });
  },
);
