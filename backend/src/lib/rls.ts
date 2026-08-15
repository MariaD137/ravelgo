/**
 * Row-level security session context for the three financial tables
 * (DriverBankAccount, Payment, Payout) — see prisma/migrations/*_enable_rls_financial_tables.
 *
 * This is a backstop, not the primary authorization mechanism: every route
 * still does its own requireAuth/requireRole + ownership check first. RLS
 * exists so that if an app-layer `where` clause is ever missing or wrong on
 * one of these three tables, the database itself still refuses to return or
 * write another user's row, instead of silently leaking it.
 *
 * Postgres session variables only persist for the lifetime of a
 * transaction when set with `set_config(..., true)` (the "local" flag), so
 * every RLS-scoped query must run inside the transaction returned by these
 * helpers — a plain `prisma.payout.findMany(...)` outside of one will see
 * zero rows once FORCE ROW LEVEL SECURITY is on, since no policy matches
 * with the session variables unset.
 */

import type { Prisma, PrismaClient } from "@prisma/client";
import { prisma } from "../db/prisma";

type Tx = Omit<PrismaClient, "$connect" | "$disconnect" | "$on" | "$transaction" | "$use" | "$extends">;

/** Scopes the transaction to rows owned by `userId` (DriverBankAccount.driverId / Payment.userId / Payout.driverId). */
export async function withUserContext<T>(
  userId: string,
  fn: (tx: Tx) => Promise<T>,
  options?: { timeout?: number },
): Promise<T> {
  return prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT set_config('app.user_id', ${userId}, true), set_config('app.bypass', 'false', true)`;
    return fn(tx);
  }, options);
}

/**
 * Bypasses per-row ownership scoping entirely. Use only after the caller's
 * Admin role has already been verified by requireRole, or for internal
 * system code with no single owning user (the Stripe webhook, the payout
 * batch job, test fixtures).
 */
export async function withBypass<T>(fn: (tx: Tx) => Promise<T>, options?: { timeout?: number }): Promise<T> {
  return prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT set_config('app.bypass', 'true', true)`;
    return fn(tx);
  }, options);
}

export type { Prisma };
