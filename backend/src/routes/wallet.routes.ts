import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { fromCents, moneyAmountSchema, toCents } from "../lib/money";
import { stripeClient } from "../billing/stripe";
import { Errors } from "../lib/errors";

export const walletRouter = Router();

/** The caller's wallet, created on first access so every user has exactly one. */
async function getOrCreateWallet(cognitoSub: string) {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  if (!user) throw Errors.notFound("User profile");
  const existing = await prisma.walletAccount.findUnique({ where: { userId: user.id } });
  if (existing) return existing;
  return prisma.walletAccount.create({ data: { userId: user.id } });
}

// Any authenticated user: view my wallet balance.
walletRouter.get("/wallet/me", requireAuth, async (req, res, next) => {
  try {
    const wallet = await getOrCreateWallet(req.user!.sub);
    res.json({ balance: fromCents(wallet.balanceCents), currency: wallet.currency });
  } catch (err) {
    next(err);
  }
});

// Any authenticated user: view my wallet transaction history.
walletRouter.get("/wallet/transactions", requireAuth, async (req, res, next) => {
  try {
    const wallet = await getOrCreateWallet(req.user!.sub);
    const transactions = await prisma.walletTransaction.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
    res.json(
      transactions.map((t) => ({
        id: t.id,
        type: t.type,
        status: t.status,
        amount: fromCents(t.amountCents),
        tripId: t.tripId,
        createdAt: t.createdAt,
      })),
    );
  } catch (err) {
    next(err);
  }
});

const topUpSchema = z.object({ amount: moneyAmountSchema });

// Any authenticated user: top up the wallet. Creates a real Stripe
// PaymentIntent and a PENDING credit; the balance is only credited once
// Stripe confirms the charge via POST /billing/webhook (see billing.routes.ts).
// The money is never trusted from the client — it moves only on the signed
// webhook, exactly like a trip card charge.
walletRouter.post("/wallet/topup", sensitiveLimiter, requireAuth, async (req, res, next) => {
  try {
    const parsed = topUpSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const wallet = await getOrCreateWallet(req.user!.sub);

    const intent = await stripeClient.paymentIntents.create({
      amount: toCents(parsed.data.amount),
      currency: wallet.currency.toLowerCase(),
      metadata: { type: "wallet_topup", walletId: wallet.id },
    });

    await prisma.walletTransaction.create({
      data: {
        walletId: wallet.id,
        type: "TOPUP",
        status: "PENDING",
        amountCents: toCents(parsed.data.amount),
        providerReference: intent.id,
      },
    });

    res.status(201).json({ clientSecret: intent.client_secret, amount: parsed.data.amount, status: "PENDING" });
  } catch (err) {
    next(err);
  }
});
