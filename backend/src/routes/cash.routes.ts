import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";

export const cashRouter = Router();

function driverName(u: { firstName: string; lastName: string } | null | undefined) {
  if (!u) return "";
  return `${u.firstName} ${u.lastName}`.trim();
}

const ROUNDING_TOLERANCE = 0.01;

/**
 * Admin (any preset — reads stay open, matching every other admin list
 * endpoint): per-driver physical-cash reconciliation.
 *
 * "Expected cash" is what the driver actually OWES RavelGo for CASH
 * trips/deliveries — i.e. the commission RavelGo would otherwise have
 * deducted from a bank payout, sourced from the ledger's real, settled
 * commissionAmount (services/ledger.ts), never a client-asserted figure and
 * never the full fare (a driver keeps the rest of a cash fare themselves —
 * see services/payouts.ts, which correspondingly excludes CASH earnings from
 * the bank-payout gross so commission is never charged twice). "Submitted" is
 * the sum of CashRemittance rows an admin has recorded for that driver.
 * Outstanding = expected - submitted; a negative outstanding (driver
 * submitted MORE than the system expected) is flagged REVIEW_REQUIRED rather
 * than silently netted, since it usually means a remittance was recorded
 * against the wrong driver or a ledger entry is missing.
 */
const CASH_ROW_CAP = 5000;

cashRouter.get("/admin/cash-reconciliation", requireAuth, requireActiveAdmin, async (_req, res) => {
  const ledgerWhere = {
    paymentMethod: "CASH" as const,
    type: { in: ["RIDE_FARE" as const, "DELIVERY_FARE" as const] },
    status: "SETTLED" as const,
  };

  // Counted separately from the capped fetch below so a truncated result is
  // never presented to an admin as the complete ledger — a financial screen
  // must say so explicitly rather than silently under-reporting what a
  // driver owes.
  const [cashLedgerRows, remittances, ledgerTotalCount, remittanceTotalCount] = await Promise.all([
    prisma.financialTransaction.findMany({ where: ledgerWhere, take: CASH_ROW_CAP }),
    prisma.cashRemittance.findMany({ take: CASH_ROW_CAP }),
    prisma.financialTransaction.count({ where: ledgerWhere }),
    prisma.cashRemittance.count(),
  ]);
  const truncated = ledgerTotalCount > CASH_ROW_CAP || remittanceTotalCount > CASH_ROW_CAP;

  const expectedByDriver = new Map<string, { total: number; count: number }>();
  for (const row of cashLedgerRows) {
    const driverId = row.driverId;
    if (!driverId) continue;
    const entry = expectedByDriver.get(driverId) ?? { total: 0, count: 0 };
    entry.total += row.commissionAmount;
    entry.count += 1;
    expectedByDriver.set(driverId, entry);
  }

  const submittedByDriver = new Map<string, number>();
  for (const r of remittances) {
    submittedByDriver.set(r.driverId, (submittedByDriver.get(r.driverId) ?? 0) + r.amount);
  }

  const driverIds = new Set([...expectedByDriver.keys(), ...submittedByDriver.keys()]);
  const drivers = await prisma.driver.findMany({
    where: { id: { in: [...driverIds] } },
    include: { user: true },
  });

  const rows = drivers.map((d) => {
    const expected = expectedByDriver.get(d.id)?.total ?? 0;
    const cashTripCount = expectedByDriver.get(d.id)?.count ?? 0;
    const submitted = submittedByDriver.get(d.id) ?? 0;
    const outstanding = Math.round((expected - submitted) * 100) / 100;
    const status = outstanding > ROUNDING_TOLERANCE ? "OUTSTANDING" : outstanding < -ROUNDING_TOLERANCE ? "REVIEW_REQUIRED" : "CLEAR";
    return {
      driverId: d.id,
      driverName: driverName(d.user),
      driverEmail: d.user.email,
      expectedCash: expected,
      cashTripCount,
      submittedCash: submitted,
      outstandingCash: outstanding,
      status,
    };
  });

  rows.sort((a, b) => b.outstandingCash - a.outstandingCash);
  res.json({
    rows,
    // True only when the underlying ledger/remittance history has grown
    // past what this endpoint fetches in one call — the per-driver figures
    // above would then be computed from an incomplete slice of history, so
    // the Admin App must say so rather than presenting them as complete.
    truncated,
    ledgerRowCount: ledgerTotalCount,
    remittanceRowCount: remittanceTotalCount,
  });
});

const remittanceSchema = z.object({
  driverId: z.string().min(1),
  amount: z.number().finite().positive(),
  note: z.string().max(500).optional(),
});

// Finance/Super Admin: record that a driver has physically handed in cash.
// This is a financial adjustment (P0 UX rule: confirm before submitting,
// enforced by the admin app's confirmation dialog) and is always audited.
cashRouter.post("/admin/cash-remittances", requireAuth, requireAdminPermission("cash:write"), async (req, res) => {
  const parsed = remittanceSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await prisma.driver.findUnique({ where: { id: parsed.data.driverId } });
  if (!driver) return res.status(404).json({ error: "Driver not found" });

  const remittance = await prisma.cashRemittance.create({
    data: {
      driverId: parsed.data.driverId,
      amount: parsed.data.amount,
      note: parsed.data.note,
      recordedBy: req.user!.email ?? req.user!.sub,
    },
  });
  // Awaited (unlike most recordAudit call sites) so a caller — or a test
  // reading the audit trail straight back — can never observe this response
  // before the audit row actually exists. recordAudit never throws, so this
  // can't turn a real failure into one.
  await recordAudit({
    actorSub: req.user!.sub,
    action: "CASH_REMITTANCE_RECORDED",
    entityType: "Driver",
    entityId: driver.id,
    metadata: { amount: parsed.data.amount, note: parsed.data.note },
  });
  res.status(201).json(remittance);
});
