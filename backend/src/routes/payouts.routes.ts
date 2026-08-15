/**
 * Driver payout routes (PAY-03).
 * Endpoints for managing driver payouts and bank account information.
 */

import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { validate } from "../lib/validate";
import { Errors } from "../lib/errors";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { decryptField, encryptField, maskLast4 } from "../lib/encryption";
import {
  calculatePayoutForPeriod,
  createPayout,
  processPayout,
  completePayout,
  failPayout,
} from "../services/payouts";

export const payoutsRouter = Router();

// Bank account schemas
const bankAccountSchema = z.object({
  accountHolderName: z.string().min(1),
  bankName: z.string().min(1),
  accountNumber: z.string().min(8),
  routingNumber: z.string().min(9),
  accountType: z.enum(["CHECKING", "SAVINGS"]).optional(),
});

// DriverBankAccount/Payout.driverId is a FK to User.id, not the Cognito
// sub — every driver-facing route here needs to resolve the real User.id
// first (an earlier version used req.user!.sub directly, which either
// violated the FK constraint on create or silently matched nothing on
// read, since no User row's id is ever equal to its own cognitoSub).
async function requireOwnUserId(cognitoSub: string): Promise<string> {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  if (!user) throw Errors.notFound("Driver profile");
  return user.id;
}

// accountNumber/routingNumber are stored encrypted — decrypt only to
// compute the last-4 mask, never return the ciphertext or a full value.
function maskBankAccount<T extends { accountNumber: string; routingNumber: string }>(
  account: T,
): Omit<T, "accountNumber" | "routingNumber"> & { accountNumber: string; routingNumber: string } {
  return {
    ...account,
    accountNumber: maskLast4(decryptField(account.accountNumber)),
    routingNumber: maskLast4(decryptField(account.routingNumber)),
  };
}

// Driver: register/update bank account for payouts
payoutsRouter.post("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const data = validate<typeof bankAccountSchema._output>(bankAccountSchema, req.body, "Request body");
    const userId = await requireOwnUserId(req.user!.sub);
    const encrypted = {
      ...data,
      accountNumber: encryptField(data.accountNumber),
      routingNumber: encryptField(data.routingNumber),
    };

    const existing = await prisma.driverBankAccount.findUnique({
      where: { driverId: userId },
    });

    let bankAccount;
    if (existing) {
      bankAccount = await prisma.driverBankAccount.update({
        where: { driverId: userId },
        data: { ...encrypted, isVerified: false }, // Re-verify when updated
      });
    } else {
      bankAccount = await prisma.driverBankAccount.create({
        data: { driverId: userId, ...encrypted },
      });
    }

    res.status(201).json({
      ...bankAccount,
      accountNumber: maskLast4(data.accountNumber),
      routingNumber: maskLast4(data.routingNumber),
    });
  } catch (err) {
    next(err);
  }
});

// Driver: get my bank account
payoutsRouter.get("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const userId = await requireOwnUserId(req.user!.sub);
    const bankAccount = await prisma.driverBankAccount.findUnique({
      where: { driverId: userId },
    });
    if (!bankAccount) throw Errors.notFound("Bank account");
    // Never return a decrypted full account/routing number over the API —
    // last 4 digits is enough for the owner to confirm which account is on
    // file; full numbers are only decrypted server-side when actually
    // initiating a transfer.
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
    const userId = await requireOwnUserId(req.user!.sub);

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where: { driverId: userId },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      prisma.payout.count({ where: { driverId: userId } }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});

// Driver: get a specific payout detail
payoutsRouter.get("/payouts/:id", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const userId = await requireOwnUserId(req.user!.sub);
    const payout = await prisma.payout.findFirst({
      where: { id: req.params.id, driverId: userId },
    });
    if (!payout) throw Errors.notFound("Payout");
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: calculate payout for a driver and period
payoutsRouter.post("/payouts/calculate", requireAuth, requireRole("Admin"), async (req, res, next) => {
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
payoutsRouter.post("/payouts/create", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const schema = z.object({
      driverId: z.string(),
      period: z.string().regex(/^\d{4}-\d{2}$/),
      amount: z.number().positive().optional(),
      reason: z.string().min(1).optional(),
    });
    const { driverId, period, amount, reason } = validate<typeof schema._output>(schema, req.body, "Request body");

    if (amount && !reason) {
      return res.status(400).json({ error: "reason is required when overriding amount" });
    }

    const driver = await prisma.user.findUnique({
      where: { id: driverId },
    });
    if (!driver || driver.role !== "DRIVER") {
      throw Errors.notFound("Driver");
    }

    const existing = await prisma.payout.findFirst({
      where: { driverId, period },
    });
    if (existing) {
      return res.status(409).json({ error: `Payout already exists for ${period}`, payoutId: existing.id });
    }

    let payout;
    if (amount) {
      payout = await prisma.payout.create({
        data: {
          driverId,
          amount,
          period,
          status: "PENDING",
          notes: `Manual override by ${req.user!.sub}: ${reason}`,
        },
      });
    } else {
      const calculation = await calculatePayoutForPeriod(driverId, period);
      payout = await createPayout(calculation);
    }

    res.status(201).json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: process a pending payout
payoutsRouter.post("/payouts/:id/process", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const payout = await processPayout(req.params.id);
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: mark payout as completed
payoutsRouter.post("/payouts/:id/complete", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const schema = z.object({ transactionId: z.string().optional() });
    const { transactionId } = validate<typeof schema._output>(schema, req.body, "Request body");
    const payout = await completePayout(req.params.id, transactionId);
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: mark payout as failed
payoutsRouter.post("/payouts/:id/fail", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const schema = z.object({ failureReason: z.string() });
    const { failureReason } = validate<typeof schema._output>(schema, req.body, "Request body");
    const payout = await failPayout(req.params.id, failureReason);
    res.json(payout);
  } catch (err) {
    next(err);
  }
});

// Admin: list all payouts with filtering
payoutsRouter.get("/payouts", requireAuth, requireRole("Admin"), async (req, res, next) => {
  try {
    const { page, pageSize } = validate<{ page: number; pageSize: number }>(
      paginationQuerySchema,
      req.query,
      "Query parameters",
    );

    const validStatuses = ["PENDING", "PROCESSING", "COMPLETED", "FAILED"] as const;
    const rawStatus = req.query.status ? String(req.query.status) : undefined;
    const status =
      rawStatus && (validStatuses as readonly string[]).includes(rawStatus)
        ? (rawStatus as (typeof validStatuses)[number])
        : undefined;
    const driverId = req.query.driverId ? String(req.query.driverId) : undefined;

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where: {
          ...(status && { status }),
          ...(driverId && { driverId }),
        },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
        include: {
          driver: { select: { id: true, firstName: true, lastName: true, email: true } },
        },
      }),
      prisma.payout.count({
        where: {
          ...(status && { status }),
          ...(driverId && { driverId }),
        },
      }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});
