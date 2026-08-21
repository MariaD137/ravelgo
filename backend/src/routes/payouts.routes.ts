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
import {
  calculatePayoutForPeriod,
  createPayout,
  getPayoutHistory,
  processPayout,
  completePayout,
  failPayout,
} from "../services/payouts";

export const payoutsRouter = Router();

// Payout.driverId and DriverBankAccount.driverId are foreign keys to
// User.id (see prisma/schema.prisma), not the Cognito sub — resolve the
// caller's own User row first, the same cognitoSub -> User.id pattern used
// everywhere else in the app (e.g. findOwnDriver() in vehicles.routes.ts,
// riders.routes.ts's /riders/me). Also confirms the caller actually has a
// User row and a DRIVER role, not just the Driver Cognito group.
async function findOwnDriverUser(cognitoSub: string) {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  if (!user || user.role !== "DRIVER") return null;
  return user;
}

// Bank account schemas
const bankAccountSchema = z.object({
  accountHolderName: z.string().min(1),
  bankName: z.string().min(1),
  accountNumber: z.string().min(8),
  routingNumber: z.string().min(9),
  accountType: z.enum(["CHECKING", "SAVINGS"]).optional(),
});

// Driver: register/update bank account for payouts
payoutsRouter.post("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const data = validate<typeof bankAccountSchema._output>(bankAccountSchema, req.body, "Request body");

    const user = await findOwnDriverUser(req.user!.sub);
    if (!user) throw Errors.notFound("Driver profile");

    const existing = await prisma.driverBankAccount.findUnique({
      where: { driverId: user.id },
    });

    let bankAccount;
    if (existing) {
      bankAccount = await prisma.driverBankAccount.update({
        where: { driverId: user.id },
        data: { ...data, isVerified: false }, // Re-verify when updated
      });
    } else {
      bankAccount = await prisma.driverBankAccount.create({
        data: { driverId: user.id, ...data },
      });
    }

    res.status(201).json(bankAccount);
  } catch (err) {
    next(err);
  }
});

// Driver: get my bank account
payoutsRouter.get("/payouts/bank-account", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const user = await findOwnDriverUser(req.user!.sub);
    if (!user) throw Errors.notFound("Driver profile");

    const bankAccount = await prisma.driverBankAccount.findUnique({
      where: { driverId: user.id },
    });
    if (!bankAccount) throw Errors.notFound("Bank account");
    res.json(bankAccount);
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

    const user = await findOwnDriverUser(req.user!.sub);
    if (!user) throw Errors.notFound("Driver profile");

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where: { driverId: user.id },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      prisma.payout.count({ where: { driverId: user.id } }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});

// Driver: get a specific payout detail
payoutsRouter.get("/payouts/:id", requireAuth, requireRole("Driver"), async (req, res, next) => {
  try {
    const user = await findOwnDriverUser(req.user!.sub);
    if (!user) throw Errors.notFound("Driver profile");

    const payout = await prisma.payout.findFirst({
      where: { id: req.params.id, driverId: user.id },
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
      amount: z.number().positive().optional(), // Override calculated amount if needed
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

    const status = req.query.status ? String(req.query.status) : undefined;
    const driverId = req.query.driverId ? String(req.query.driverId) : undefined;

    const [payouts, total] = await Promise.all([
      prisma.payout.findMany({
        where: {
          ...(status && { status: status as any }),
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
          ...(status && { status: status as any }),
          ...(driverId && { driverId }),
        },
      }),
    ]);

    res.json(paginate(payouts, total, page, pageSize));
  } catch (err) {
    next(err);
  }
});
