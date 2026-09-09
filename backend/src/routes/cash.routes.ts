import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
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
cashRouter.get("/admin/cash-reconciliation", requireAuth, requireRole("Admin"), async (_req, res) => {
  const [cashLedgerRows, remittances] = await Promise.all([
    prisma.financialTransaction.findMany({
      where: { paymentMethod: "CASH", type: { in: ["RIDE_FARE", "DELIVERY_FARE"] }, status: "SETTLED" },
      take: 5000,
    }),
    prisma.cashRemittance.findMany({ take: 5000 }),
  ]);

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
  res.json(rows);
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
