import { prisma } from "../db/prisma";
import { SETTINGS_ID } from "./payment-rules";

/**
 * The referral programme's configuration, read from the single AppSetting
 * row (the same row payment-rules.ts owns — this app has exactly one).
 *
 * Every number here is a business decision, not a constant: what a referral
 * is worth and how much the new rider has to actually do before anyone is
 * paid are things an admin sets from the admin app
 * (PATCH /api/admin/settings/referral), and every change is audited.
 *
 * The defaults below are what the programme looks like before anyone has
 * touched it, and the most important one is that it is OFF.
 */
export interface ReferralProgramSettings {
  /** No code is issued, no claim is accepted and nothing is paid while false. */
  enabled: boolean;
  /** NGN credited to the referrer when their referee qualifies. */
  rewardAmount: number;
  /** NGN credited to the new rider at the same moment. 0 = referrer-only. */
  refereeRewardAmount: number;
  /** COMPLETED trips the new rider must make before either side is paid. */
  qualifyingTrips: number;
}

export const DEFAULT_REFERRAL_REWARD_AMOUNT = 1000;
export const DEFAULT_REFERRAL_QUALIFYING_TRIPS = 1;

/**
 * Read the programme. Uses the same upsert-on-read pattern as
 * getPaymentSettings so there is no separate seed step and no code path that
 * has to cope with a missing row.
 */
export async function getReferralProgram(): Promise<ReferralProgramSettings> {
  const row = await prisma.appSetting.upsert({
    where: { id: SETTINGS_ID },
    update: {},
    create: { id: SETTINGS_ID },
  });
  return {
    enabled: row.referralEnabled,
    rewardAmount: row.referralRewardAmount,
    refereeRewardAmount: row.referralRefereeRewardAmount,
    qualifyingTrips: row.referralQualifyingTrips,
  };
}

// Deliberately excludes 0/O/1/I/L to keep a code readable when someone reads
// it aloud or copies it off a screenshot — a referral code's whole job is to
// survive being retyped by hand.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const REFERRAL_CODE_LENGTH = 8;

/** A random code from the unambiguous alphabet. Not a uniqueness guarantee. */
export function generateReferralCode(random: () => number = Math.random): string {
  let out = "";
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i += 1) {
    out += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  }
  return out;
}

/**
 * How a code is compared. Codes are handed over verbally and retyped, so
 * matching is case-insensitive and ignores surrounding whitespace — but the
 * stored form is always upper case, so lookups stay a plain indexed equality
 * check rather than a scan.
 */
export function normalizeReferralCode(input: string): string {
  return input.trim().toUpperCase();
}
