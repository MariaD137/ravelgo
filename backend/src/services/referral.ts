import type { Prisma, Referral } from "@prisma/client";
import { prisma } from "../db/prisma";
import { toCents } from "../lib/money";
import { notifyUser } from "../lib/notifications";
import {
  generateReferralCode,
  getReferralProgram,
  normalizeReferralCode,
  type ReferralProgramSettings,
} from "../lib/referral-rules";

/**
 * Rider-to-rider referrals, end to end: issuing a code, claiming someone
 * else's, and paying both sides once the new rider has actually ridden.
 *
 * The money is the reason this is a service and not a route handler. Two
 * wallet credits, two ledger rows and a status change have to happen
 * together or not at all, exactly once, even though the trigger (a trip
 * completing) can fire repeatedly and concurrently.
 */

/** Why a claim was refused. The route maps these to status codes. */
export type ClaimFailure =
  | "PROGRAM_DISABLED"
  | "UNKNOWN_CODE"
  | "SELF_REFERRAL"
  | "ALREADY_REFERRED"
  | "NOT_A_NEW_RIDER";

export type ClaimResult = { ok: true; referral: Referral } | { ok: false; reason: ClaimFailure };

// How many times to retry on a code collision before giving up. With a
// 31-character alphabet and 8 characters there are ~8.5e11 codes, so a
// collision is already vanishingly unlikely; this just makes it impossible
// for one to surface as a 500.
const CODE_ISSUE_ATTEMPTS = 5;

/**
 * This rider's code, issued on first read and stable thereafter.
 *
 * Issued lazily rather than at signup so the column stays null for everyone
 * who never opens the invite screen, and so an existing user base needs no
 * backfill — the first person to look gets one.
 */
export async function getOrCreateReferralCode(userId: string): Promise<string> {
  const existing = await prisma.user.findUniqueOrThrow({
    where: { id: userId },
    select: { referralCode: true },
  });
  if (existing.referralCode) return existing.referralCode;

  for (let attempt = 0; attempt < CODE_ISSUE_ATTEMPTS; attempt += 1) {
    const code = generateReferralCode();
    try {
      const updated = await prisma.user.update({
        where: { id: userId },
        data: { referralCode: code },
        select: { referralCode: true },
      });
      return updated.referralCode as string;
    } catch (err) {
      // P2002 = someone else already holds this code. Try another.
      if ((err as { code?: string }).code !== "P2002") throw err;
    }
  }
  throw new Error("Could not issue a unique referral code");
}

/**
 * A new rider claims someone else's code.
 *
 * Every refusal here is an anti-abuse rule, not a validation nicety:
 *
 *  - SELF_REFERRAL   nobody pays themselves for existing.
 *  - ALREADY_REFERRED one referral per person, ever. Enforced again by the
 *                     unique index on Referral.refereeId, so even a race
 *                     between two concurrent claims can only write one.
 *  - NOT_A_NEW_RIDER  the point is to bring in NEW riders, so an account
 *                     that has already completed a trip cannot retroactively
 *                     attribute itself to a friend.
 *  - PROGRAM_DISABLED no claims accumulate while the programme is off, so
 *                     turning it on later cannot trigger a backlog of payouts
 *                     nobody budgeted for.
 */
export async function claimReferralCode(refereeId: string, rawCode: string): Promise<ClaimResult> {
  const program = await getReferralProgram();
  if (!program.enabled) return { ok: false, reason: "PROGRAM_DISABLED" };

  const code = normalizeReferralCode(rawCode);
  const referrer = await prisma.user.findUnique({
    where: { referralCode: code },
    select: { id: true, deletedAt: true },
  });
  // A deleted referrer's code stops working — it must not keep earning.
  if (!referrer || referrer.deletedAt) return { ok: false, reason: "UNKNOWN_CODE" };
  if (referrer.id === refereeId) return { ok: false, reason: "SELF_REFERRAL" };

  const alreadyReferred = await prisma.referral.findUnique({ where: { refereeId } });
  if (alreadyReferred) return { ok: false, reason: "ALREADY_REFERRED" };

  const completedTrips = await prisma.trip.count({
    where: { riderId: refereeId, status: "COMPLETED" },
  });
  if (completedTrips > 0) return { ok: false, reason: "NOT_A_NEW_RIDER" };

  try {
    const referral = await prisma.referral.create({
      data: { referrerId: referrer.id, refereeId, code },
    });
    return { ok: true, referral };
  } catch (err) {
    // Lost a race with a concurrent claim — the unique index held.
    if ((err as { code?: string }).code === "P2002") {
      return { ok: false, reason: "ALREADY_REFERRED" };
    }
    throw err;
  }
}

/**
 * Called when a rider completes a trip. Pays out their referral if this was
 * the trip that qualified it.
 *
 * Never throws: it is invoked from the trip-status route, and a referral
 * problem must not fail a trip that genuinely completed. A failure simply
 * leaves the row PENDING, and the next completed trip retries it — so the
 * only cost of a transient error is a delayed reward, never a lost one.
 */
export async function maybeRewardReferral(refereeId: string): Promise<Referral | null> {
  try {
    return await rewardReferralForReferee(refereeId);
  } catch (err) {
    console.error("Failed to settle referral reward", err);
    return null;
  }
}

async function rewardReferralForReferee(refereeId: string): Promise<Referral | null> {
  const referral = await prisma.referral.findUnique({ where: { refereeId } });
  if (!referral || referral.status !== "PENDING") return null;

  const program = await getReferralProgram();
  // A programme switched off after a claim stops paying. The row stays
  // PENDING and pays if it is switched back on.
  if (!program.enabled) return null;

  const completedTrips = await prisma.trip.count({
    where: { riderId: refereeId, status: "COMPLETED" },
  });
  if (completedTrips < program.qualifyingTrips) return null;

  const rewarded = await payReferral(referral.id, referral.referrerId, refereeId, program);
  if (!rewarded) return null;

  await notifyReferralPaid(referral.referrerId, refereeId, program);
  return rewarded;
}

/**
 * The payout itself: both wallet credits, both ledger rows and the status
 * change, in ONE transaction.
 *
 * The guard against paying twice is the conditional update at the end —
 * `updateMany` on `status: "PENDING"`. If a concurrent caller (two trips
 * completing at once, a retry racing the original) already flipped the row,
 * this one writes nothing and the whole transaction rolls back, taking its
 * wallet credits with it. That is why the credits are inside the transaction
 * and the status change is last.
 */
async function payReferral(
  referralId: string,
  referrerId: string,
  refereeId: string,
  program: ReferralProgramSettings,
): Promise<Referral | null> {
  try {
    return await prisma.$transaction(async (tx) => {
      await creditWallet(tx, referrerId, program.rewardAmount);
      await creditWallet(tx, refereeId, program.refereeRewardAmount);

      const { count } = await tx.referral.updateMany({
        where: { id: referralId, status: "PENDING" },
        data: {
          status: "REWARDED",
          rewardedAt: new Date(),
          referrerRewardAmount: program.rewardAmount,
          refereeRewardAmount: program.refereeRewardAmount,
        },
      });
      // Someone else got there first: undo this transaction's credits.
      if (count === 0) throw new ReferralAlreadySettled();

      return tx.referral.findUniqueOrThrow({ where: { id: referralId } });
    });
  } catch (err) {
    if (err instanceof ReferralAlreadySettled) return null;
    throw err;
  }
}

/** Internal signal used to roll the payout transaction back; never surfaces. */
class ReferralAlreadySettled extends Error {}

/**
 * Credit a rider's wallet, creating the account if they never had one (a
 * brand-new rider usually hasn't). A zero amount writes nothing at all, so
 * the referee-reward-of-0 default leaves no confusing ₦0 row in anyone's
 * wallet history.
 */
async function creditWallet(tx: Prisma.TransactionClient, userId: string, amount: number): Promise<void> {
  if (amount <= 0) return;
  const wallet = await tx.walletAccount.upsert({
    where: { userId },
    update: {},
    create: { userId },
    select: { id: true },
  });
  await tx.walletAccount.update({
    where: { id: wallet.id },
    data: { balanceCents: { increment: toCents(amount) } },
  });
  await tx.walletTransaction.create({
    data: {
      walletId: wallet.id,
      type: "REFERRAL_BONUS",
      status: "COMPLETED",
      amountCents: toCents(amount),
    },
  });
}

async function notifyReferralPaid(
  referrerId: string,
  refereeId: string,
  program: ReferralProgramSettings,
): Promise<void> {
  await notifyUser(
    referrerId,
    "REFERRAL_REWARDED",
    "Referral reward earned",
    `Someone you invited took their first ride. ${program.rewardAmount} has been added to your wallet.`,
  );
  if (program.refereeRewardAmount > 0) {
    await notifyUser(
      refereeId,
      "REFERRAL_REWARDED",
      "Welcome bonus added",
      `${program.refereeRewardAmount} has been added to your wallet for joining through a friend's invite.`,
    );
  }
}

/** What the invite screen shows: the rider's own code and how it is doing. */
export interface ReferralSummary {
  code: string;
  program: ReferralProgramSettings;
  pending: number;
  rewarded: number;
  totalEarned: number;
  /** The referral that brought THIS rider in, if any. */
  referredByCode: string | null;
  /** Whether this rider could still claim someone's code. */
  canClaim: boolean;
}

export async function getReferralSummary(userId: string): Promise<ReferralSummary> {
  const program = await getReferralProgram();
  const code = await getOrCreateReferralCode(userId);

  const [made, mine, completedTrips] = await Promise.all([
    prisma.referral.findMany({
      where: { referrerId: userId },
      select: { status: true, referrerRewardAmount: true },
    }),
    prisma.referral.findUnique({ where: { refereeId: userId }, select: { code: true } }),
    prisma.trip.count({ where: { riderId: userId, status: "COMPLETED" } }),
  ]);

  return {
    code,
    program,
    pending: made.filter((r) => r.status === "PENDING").length,
    rewarded: made.filter((r) => r.status === "REWARDED").length,
    totalEarned: made.reduce((sum, r) => sum + (r.referrerRewardAmount ?? 0), 0),
    referredByCode: mine?.code ?? null,
    canClaim: program.enabled && !mine && completedTrips === 0,
  };
}
