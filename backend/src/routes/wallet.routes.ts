import { randomUUID } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { sensitiveLimiter } from "../middleware/rate-limit";
import { fromCents, moneyAmountSchema, toCents } from "../lib/money";
import { paystackClient } from "../billing/paystack";
import { Errors } from "../lib/errors";

export const walletRouter = Router();

/** Get or lazily create the single wallet for a given internal user id. */
async function getOrCreateWalletForUserId(userId: string) {
  const existing = await prisma.walletAccount.findUnique({ where: { userId } });
  if (existing) return existing;
  return prisma.walletAccount.create({ data: { userId } });
}

/** The caller's wallet, created on first access so every user has exactly one. */
async function getOrCreateWallet(cognitoSub: string) {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  if (!user) throw Errors.notFound("User profile");
  return getOrCreateWalletForUserId(user.id);
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

const topUpSchema = z.object({
  amount: moneyAmountSchema,
  // Optional: fund SOMEONE ELSE'S wallet ("send money"). When present the
  // authenticated caller is the payer (their card is charged via Paystack) and
  // this names the beneficiary whose balance is credited on webhook success.
  // Omit to top up your own wallet.
  beneficiaryEmail: z.string().email().optional(),
});

// Any authenticated user: top up a wallet — their own, or (with
// beneficiaryEmail) an authorized third party's. Either way this initializes
// a real Paystack transaction and a PENDING credit; the balance is only
// credited once Paystack confirms the charge via POST /billing/webhook
// (verified against Paystack's own verify endpoint first). The money is
// never trusted from the client and moves only on the signed, verified
// webhook, so a caller can only ever ADD funds (their own money) to a
// wallet — never move funds out of one — which is what makes third-party
// funding safe without extra consent.
walletRouter.post("/wallet/topup", sensitiveLimiter, requireAuth, async (req, res, next) => {
  try {
    const parsed = topUpSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const payerSub = req.user!.sub;
    const payer = await prisma.user.findUnique({ where: { cognitoSub: payerSub } });
    if (!payer) throw Errors.notFound("User profile");

    let wallet;
    let fundedBySub: string | undefined;

    if (parsed.data.beneficiaryEmail) {
      const beneficiary = await prisma.user.findUnique({
        where: { email: parsed.data.beneficiaryEmail },
      });
      if (!beneficiary) throw Errors.notFound("Beneficiary");
      wallet = await getOrCreateWalletForUserId(beneficiary.id);
      // Only record a third-party funder when it really is someone else, so a
      // user topping up their own wallet by email still reads as a self top-up.
      if (beneficiary.cognitoSub !== payerSub) fundedBySub = payerSub;
    } else {
      wallet = await getOrCreateWalletForUserId(payer.id);
    }

    // Every top-up needs its own reference (unlike a one-shot trip/delivery
    // charge, a wallet may legitimately be topped up many times), so this is
    // random rather than derived from the wallet/booking id.
    const reference = `ravelgo_topup_${randomUUID()}`;
    const { authorizationUrl } = await paystackClient.initializeTransaction({
      email: payer.email,
      amountKobo: toCents(parsed.data.amount),
      reference,
      currency: wallet.currency,
      metadata: { type: "wallet_topup", walletId: wallet.id, fundedBy: fundedBySub ?? payerSub },
    });

    await prisma.walletTransaction.create({
      data: {
        walletId: wallet.id,
        type: "TOPUP",
        status: "PENDING",
        amountCents: toCents(parsed.data.amount),
        provider: "PAYSTACK",
        providerReference: reference,
        fundedBySub,
      },
    });

    res.status(201).json({
      authorizationUrl,
      amount: parsed.data.amount,
      status: "PENDING",
      beneficiary: fundedBySub ? parsed.data.beneficiaryEmail : undefined,
    });
  } catch (err) {
    next(err);
  }
});
