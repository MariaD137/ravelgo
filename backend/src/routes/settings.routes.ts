import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { CASH_CURRENCY, getPaymentSettings, SETTINGS_ID } from "../lib/payment-rules";

export const settingsRouter = Router();

// Any authenticated user (rider, driver or admin): the current payment rules.
// The rider app needs this to disable Cash above the limit *before* the
// backend would reject it — but this is display-only; settleTripPayment
// re-checks the same rule server-side regardless of what the client shows.
settingsRouter.get("/settings/payment", requireAuth, async (_req, res) => {
  const settings = await getPaymentSettings();
  res.json({ ...settings, currency: CASH_CURRENCY });
});

const updateSettingsSchema = z.object({
  cashPaymentLimit: z.number().finite().positive().max(1_000_000).optional(),
  cashPaymentEnabled: z.boolean().optional(),
  cardPaymentEnabled: z.boolean().optional(),
  walletPaymentEnabled: z.boolean().optional(),
});

// Super Admin only: change payment rules. Every change is audited with the
// old and new value, matching the product's "ADMIN / ACTION / OLD VALUE / NEW
// VALUE" audit record requirement for sensitive financial configuration.
settingsRouter.patch(
  "/admin/settings/payment",
  requireAuth,
  requireAdminPermission("settings:write"),
  async (req, res) => {
    const parsed = updateSettingsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
    if (Object.keys(parsed.data).length === 0) {
      return res.status(400).json({ error: "No settings provided" });
    }

    const before = await getPaymentSettings();
    const updated = await prisma.appSetting.upsert({
      where: { id: SETTINGS_ID },
      update: parsed.data,
      create: { id: SETTINGS_ID, ...parsed.data },
    });

    for (const [key, newValue] of Object.entries(parsed.data)) {
      const oldValue = (before as unknown as Record<string, unknown>)[key];
      if (oldValue !== newValue) {
        void recordAudit({
          actorSub: req.user!.sub,
          action: "PAYMENT_SETTING_CHANGED",
          entityType: "AppSetting",
          entityId: SETTINGS_ID,
          metadata: { field: key, oldValue, newValue },
        });
      }
    }

    res.json({
      cashPaymentLimit: updated.cashPaymentLimit,
      cashPaymentEnabled: updated.cashPaymentEnabled,
      cardPaymentEnabled: updated.cardPaymentEnabled,
      walletPaymentEnabled: updated.walletPaymentEnabled,
      currency: CASH_CURRENCY,
    });
  },
);
