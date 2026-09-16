/**
 * One-time backfill for security audit Finding A1.
 *
 * `POST /admin-users` used to store the Cognito *Username* (which, for an
 * admin created that way, is the email — see cognitoGroups.createAdminUser's
 * doc comment) as `User.cognitoSub`, instead of the account's actual `sub`
 * claim. Every permission check (`effectiveAdminRole`, `isSuspendedAdmin`,
 * `GET /admin-users/me`) looks a row up by `sub`, so any admin row created
 * before that fix shipped has a `cognitoSub` that can never match — they
 * silently ran (and will keep running, until this backfill is applied) as
 * unrestricted, unsuspendable legacy SUPER_ADMINs regardless of their
 * intended preset.
 *
 * This script finds every `role: "ADMIN"` row, looks up its real Cognito
 * `sub`, and reports (or, with --apply, fixes) any row whose stored
 * `cognitoSub` doesn't match.
 *
 * SAFE BY DEFAULT: runs as a dry run — it only reads and prints a report.
 * Nothing is written to Postgres or Cognito unless you pass --apply.
 *
 * Usage:
 *   cd backend
 *   DATABASE_URL=<the real one> npx ts-node scripts/backfill-admin-cognito-sub.ts            # dry run
 *   DATABASE_URL=<the real one> npx ts-node scripts/backfill-admin-cognito-sub.ts --apply     # actually fix rows
 *
 * Requires:
 *   - DATABASE_URL pointing at the environment you want to fix (staging or
 *     production — run staging first).
 *   - AWS credentials (in the environment, same as the backend service
 *     itself uses) with cognito-idp:AdminGetUser on that environment's User
 *     Pool. COGNITO_USER_POOL_ID must also be set, same as the backend's
 *     own .env.
 *
 * Never prints, stores, or touches a password. Only reads Cognito account
 * identifiers (Username/sub) and updates the `cognitoSub` column.
 */
import {
  CognitoIdentityProviderClient,
  AdminGetUserCommand,
  UserNotFoundException,
} from "@aws-sdk/client-cognito-identity-provider";
import { env } from "../src/config/env";
import { prisma } from "../src/db/prisma";

const APPLY = process.argv.includes("--apply");

const client = new CognitoIdentityProviderClient({ region: env.AWS_REGION });

async function lookupRealSub(usernameOrAlias: string): Promise<string | null> {
  try {
    const result = await client.send(
      new AdminGetUserCommand({ UserPoolId: env.COGNITO_USER_POOL_ID, Username: usernameOrAlias }),
    );
    return result.UserAttributes?.find((a) => a.Name === "sub")?.Value ?? null;
  } catch (err) {
    if (err instanceof UserNotFoundException) return null;
    throw err;
  }
}

async function main() {
  console.log(`Mode: ${APPLY ? "APPLY (will write to Postgres)" : "DRY RUN (read-only, pass --apply to fix)"}`);
  console.log(`User Pool: ${env.COGNITO_USER_POOL_ID}\n`);

  const admins = await prisma.user.findMany({
    where: { role: "ADMIN" },
    select: { id: true, email: true, cognitoSub: true, adminRole: true, suspended: true },
    orderBy: { createdAt: "asc" },
  });

  let ok = 0;
  let fixed = 0;
  let wouldFix = 0;
  let orphaned = 0;
  let collisions = 0;

  for (const admin of admins) {
    // The stored cognitoSub is itself a valid Cognito identifier whether
    // it's already a real sub (nothing to fix) or the legacy Username/email
    // (what we're trying to detect) — AdminGetUser accepts either. Fall back
    // to email only if that lookup somehow finds nothing at all.
    let realSub = await lookupRealSub(admin.cognitoSub);
    if (realSub === null) {
      realSub = await lookupRealSub(admin.email);
    }

    if (realSub === null) {
      orphaned++;
      console.log(`ORPHANED  ${admin.email} (id=${admin.id}) — no matching Cognito account found by cognitoSub or email. Needs manual review.`);
      continue;
    }

    if (realSub === admin.cognitoSub) {
      ok++;
      continue;
    }

    if (!APPLY) {
      wouldFix++;
      console.log(`WOULD FIX ${admin.email} (id=${admin.id}, adminRole=${admin.adminRole ?? "null->SUPER_ADMIN"}, suspended=${admin.suspended}): cognitoSub "${admin.cognitoSub}" -> "${realSub}"`);
      continue;
    }

    try {
      await prisma.user.update({ where: { id: admin.id }, data: { cognitoSub: realSub } });
      fixed++;
      console.log(`FIXED     ${admin.email} (id=${admin.id}): cognitoSub "${admin.cognitoSub}" -> "${realSub}"`);
    } catch (err) {
      // cognitoSub is @unique — this means another row already holds the
      // real sub (a genuine duplicate/orphaned-row situation), which needs a
      // human to decide which row is correct rather than being resolved
      // automatically.
      collisions++;
      console.log(`COLLISION ${admin.email} (id=${admin.id}): wanted to set cognitoSub to "${realSub}", but another row already has it. Skipped — needs manual review.`);
      console.log(`          ${err instanceof Error ? err.message : err}`);
    }
  }

  console.log("\n--- Summary ---");
  console.log(`Scanned:        ${admins.length}`);
  console.log(`Already correct: ${ok}`);
  console.log(APPLY ? `Fixed:          ${fixed}` : `Would fix:      ${wouldFix}`);
  console.log(`Orphaned:       ${orphaned} (no Cognito account found — review manually)`);
  console.log(`Collisions:     ${collisions} (skipped — review manually)`);
  if (!APPLY && wouldFix > 0) {
    console.log("\nRe-run with --apply to write these fixes.");
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
