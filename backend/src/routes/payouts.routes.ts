/**
 * Driver payout routes (PAY-03).
 * Endpoints for managing driver payouts and bank account information.
 */

import type { PayoutStatus } from "@prisma/client";
import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { validate } from "../lib/validate";
import { Errors } from "../lib/errors";
import { moneyAmountSchema } from "../lib/money";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { containsInsensitive, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";
import { paystackClient } from "../billing/paystack";
import {
  calculatePayoutForPeriod,
  createPayout,
  processPayout,
  completePayout,
  failPayout,
  PayoutTransferFailedError,
} from "../services/payouts";

export const payoutsRouter = Router();

// Payout.driverId and DriverBankAccount.driverId are both FKs to User.id
// (see prisma/schema.prisma), not the Cognito sub and not Driver.id — every
// self-service route below must resolve the caller's real User.id first.
// Using req.user!.sub directly here previously broke bank-account writes
// with a foreign-key violation and hid a driver's own payouts from them.
async function requireOwnUserId(cognitoSub: string): Promise<string> {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  if (!user) throw Errors.notFound("Driver profile");
  return user.id;
}

/**
 * Never return full bank/routing numbers to the client — only the last 4
 * digits, so a leaked response (or shoulder-surf) can't reveal the account.
 * Full numbers stay server-side only. (Longer term these should be tokenized
 * via the payments provider rather than stored raw — see the DriverBankAccount
 * model.)
 */
function maskBankAccount<T extends { accountNumber?: string | null; routingNumber?: string | null }>(acct: T) {
  const last4 = (v?: string | null) => (v && v.length >= 4 ? `••••${v.slice(-4)}` : v ? "••••" : v);
  return { ...acct, accountNumber: last4(acct.accountNumber), routingNumber: last4(acct.routingNumber) };
}

// Bank account schemas. routingNumber is now optional — it's a US-ABA-style
// field with no Nigerian equivalent, kept only so bank accounts saved before
// the Paystack migration keep their stored value. bankCode (from
// GET /payouts/banks) is what real Paystack transfers actually key off.
const bankAccountSchema = z.object({
  accountHolderName: z.string().min(1),
  bankName: z.string().min(1),
  bankCode: z.string().min(1).optional(),
  accountNumber: z.string().min(8),
  routingNumber: z.string().min(9).optional(),
  accountType: z.enum(["CHECKING", "SAVINGS"]).optional(),
});

// Driver: get the list of banks (name + Paystack bank code) to pick from
// when entering bank-account details — the code is required for an
// automated Paystack transfer to work (see services/payouts.ts#processPayout).
payoutsRouter.get("/payouts/banks", requireAuth, requireRole("Driver"), async (_req, res, next) => {
  try {
    res.json(await paystackClient.listBanks());
  } catch (err) {
    next(err);
  }
});

// Driver: register/update bank account for payouts
payoutsRouter.post("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const data = validate<typeof bankAccountSchema._output>(bankAccountSchema, req.body, "Request body");
    const driverId = await requireOwnUserId(req.user!.sub);

    const existing = await prisma.driverBankAccount.findUnique({
      where: { driverId },
    });

    let bankAccount;
    if (existing) {
      bankAccount = await prisma.driverBankAccount.update({
        where: { driverId },
        // Re-verify when updated, and clear any cached Paystack transfer
        // recipient — it was created against the OLD account details, and
        // reusing it after an edit would send a future payout to the wrong
        // place.
        data: { ...data, isVerified: false, paystackRecipientCode: null },
      });
    } else {
      bankAccount = await prisma.driverBankAccount.create({
        data: { driverId, ...data },
      });
    }

    res.status(201).json(maskBankAccount(bankAccount));
  } catch (err) {
    next(err);
  }
});

// Driver: get my bank account
payoutsRouter.get("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driverId = await requireOwnUserId(req.user!.sub);
    const bankAccount = await prisma.driverBankAccount.findUnique({
      where: { driverId },
    });
    if (!bankAccount) throw Errors.notFound("Bank account");
    res.json(maskBankAccount(bankAccount));
  } catch (err) {
    next(err);
  }
});

// Driver: get my payout history
payoutsRouter.get("/payouts/history", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const { page, pageSize } = validate<{ page: number; pageSize: number }>(
      paginationQuerySchema,
      req.query,
      "Query parameters",
    );
    const driverId = await requireOwnUserId(req.user!.sub);

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where: { driverId },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      prisma.payout.count({ where: { driverId } }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});

// Driver: get a specific payout detail
payoutsRouter.get("/payouts/:id", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const driverId = await requireOwnUserId(req.user!.sub);
    const payout = await prisma.payout.findFirst({
      where: { id: req.params.id, driverId },
    });
    if (!payout) throw Errors.notFound("Payout");
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: calculate payout for a driver and period
payoutsRouter.post("/payouts/calculate", requireAuth, requireAdminPermission("payouts:write"), async (req, res, next) => {
  try {
    const schema = z.object({
      driverId: z.string(),
      period: z.string().regex(/^\d{4}-\d{2}$/), // YYYY-MM
    });
    const { driverId, period } = validate<typeof schema._output>(schema, req.body, "Request body");

    const driver = await prisma.user.findUnique({
      where: { id: driverId },
    });
    if (!driver || driver.role !== "DRIVER") {
      throw Errors.notFound("Driver");
    }

    const calculation = await calculatePayoutForPeriod(driverId, period);
    res.json(calculation);
  } catch (err) {
    next(err);
  }
});

// Admin: create pending payout for a driver
payoutsRouter.post("/payouts/create", sensitiveLimiter, requireAuth, requireAdminPermission("payouts:write"), async (req, res, next) => {
  try {
    const schema = z.object({
      driverId: z.string(),
      period: z.string().regex(/^\d{4}-\d{2}$/),
      // Manual override is Admin-only, but still bounded so a typo or a
      // compromised admin session can't create a nine-figure payout.
      amount: moneyAmountSchema.optional(),
    });
    const { driverId, period, amount } = validate<typeof schema._output>(schema, req.body, "Request body");

    const driver = await prisma.user.findUnique({
      where: { id: driverId },
    });
    if (!driver || driver.role !== "DRIVER") {
      throw Errors.notFound("Driver");
    }

    let payout;
    if (amount) {
      // Manual override amount
      payout = await prisma.payout.create({
        data: {
          driverId,
          amount,
          period,
          status: "PENDING",
        },
      });
    } else {
      // Calculate based on trips
      const calculation = await calculatePayoutForPeriod(driverId, period);
      payout = await createPayout(calculation);
    }

    res.status(201).json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: process a pending payout — initiates a real Paystack transfer when
// the driver's bank account has a bank code on file (see
// services/payouts.ts#processPayout); otherwise falls back to the manual
// flow completed via POST /payouts/:id/complete below.
payoutsRouter.post("/payouts/:id/process", sensitiveLimiter, requireAuth, requireAdminPermission("payouts:write"), async (req, res, next) => {
  try {
    const payout = await processPayout(req.params.id);
    res.json(payout);
  } catch (err) {
    if (err instanceof PayoutTransferFailedError) {
      return res.status(502).json({ error: err.message });
    }
    next(err);
  }
});

// Admin: mark payout as completed manually — for a payout that never
// automated (no Paystack bank code on file, see processPayout()) or one
// completed by some other means. transactionId is required (SE-4) — the
// real bank/wire reference for the transfer the admin just made outside this
// system, never a fabricated placeholder. See completePayout() for why. A
// payout processPayout() already sent through Paystack finalizes itself via
// the transfer.success/transfer.failed webhook instead — this route is the
// fallback path, not the primary one.
payoutsRouter.post(
  "/payouts/:id/complete",
  sensitiveLimiter,
  requireAuth,
  requireAdminPermission("payouts:write"),
  async (req, res, next) => {
    try {
      const schema = z.object({ transactionId: z.string().trim().min(4, "A real transaction reference is required") });
      const { transactionId } = validate<typeof schema._output>(schema, req.body, "Request body");
      const payout = await completePayout(req.params.id, transactionId);
      res.json(payout);
    } catch (err) {
      next(err);
    }
  },
);

// Admin: mark payout as failed
payoutsRouter.post("/payouts/:id/fail", requireAuth, requireAdminPermission("payouts:write"), async (req, res, next) => {
  try {
    const schema = z.object({ failureReason: z.string() });
    const { failureReason } = validate<typeof schema._output>(schema, req.body, "Request body");
    const payout = await failPayout(req.params.id, failureReason);
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: list all payouts with filtering, optionally narrowed by a ?q=
// search against the driver's name/email or the payout's transaction
// reference.
payoutsRouter.get("/payouts", requireAuth, requireActiveAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, q } = validate<{ page: number; pageSize: number; q?: string }>(
      paginationQuerySchema.merge(searchQuerySchema),
      req.query,
      "Query parameters",
    );

    const statusSchema = z.enum(["PENDING", "PROCESSING", "COMPLETED", "FAILED", "CANCELLED"]).optional();
    const status: PayoutStatus | undefined = validate<PayoutStatus | undefined>(
      statusSchema,
      req.query.status,
      "status query parameter",
    );
    const driverId = req.query.driverId ? String(req.query.driverId) : undefined;

    const where: Prisma.PayoutWhereInput = {
      ...(status && { status }),
      ...(driverId && { driverId }),
      ...(q
        ? {
            OR: [
              { transactionId: containsInsensitive(q) },
              { driver: { firstName: containsInsensitive(q) } },
              { driver: { lastName: containsInsensitive(q) } },
              { driver: { email: containsInsensitive(q) } },
            ],
          }
        : {}),
    };

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
        include: {
          driver: { select: { id: true, firstName: true, lastName: true, email: true } },
        },
      }),
      prisma.payout.count({ where }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});
