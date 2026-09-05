import {
  CognitoIdentityProviderClient,
  AdminAddUserToGroupCommand,
  AdminCreateUserCommand,
  AdminDisableUserCommand,
  AdminEnableUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { env } from "../config/env";

const client = new CognitoIdentityProviderClient({ region: env.AWS_REGION });

/**
 * Server-side Cognito group management.
 *
 * Role elevation is server-authoritative: a user's group membership — which is
 * what `requireRole` authorizes against (see middleware/auth.ts) — can ONLY be
 * changed here, by the backend using its scoped IAM role. A mobile/web client
 * has no AWS admin credentials and can never put itself into a privileged
 * group. New sign-ups get the "Rider" group from the PostConfirmation Lambda;
 * "Driver" is granted through the server-authoritative driver-application flow
 * (POST /drivers/apply), and "Admin" only ever by an operator.
 *
 * Exported as an object so tests can stub `addUserToGroup` with
 * `mock.method(cognitoGroups, "addUserToGroup", ...)` — the same pattern used
 * for the Cognito verifier and the Stripe client in the test helpers.
 */
export const cognitoGroups = {
  /**
   * Add a Cognito user to a group. Idempotent: Cognito treats adding a user to
   * a group they already belong to as a successful no-op, so this is safe to
   * call again on a retry.
   *
   * `sub` is the user's immutable Cognito subject taken from the verified
   * access token. Cognito admin APIs accept the `sub` as the `Username` value,
   * so no separate username lookup is needed.
   */
  async addUserToGroup(sub: string, group: string): Promise<void> {
    await client.send(
      new AdminAddUserToGroupCommand({
        UserPoolId: env.COGNITO_USER_POOL_ID,
        Username: sub,
        GroupName: group,
      }),
    );
  },

  /**
   * Invite a brand-new admin user: Cognito creates the account, generates a
   * temporary password, and emails it (Cognito's default invitation
   * template) since no password is supplied here — the invitee sets their
   * own permanent password on first sign-in. Only ever called from the
   * Admin-Users management routes, themselves Super-Admin-only.
   *
   * Returns the pool's actual Username for this account. We pass `email` as
   * the requested Username (valid since the pool's only sign-in alias is
   * email), but read back whatever Cognito actually assigned rather than
   * assuming — that returned value is what every other admin API in this
   * file addresses the user by, and it's what we store as cognitoSub.
   */
  async createAdminUser(params: { email: string; firstName: string; lastName: string }): Promise<{ username: string }> {
    const result = await client.send(
      new AdminCreateUserCommand({
        UserPoolId: env.COGNITO_USER_POOL_ID,
        Username: params.email,
        UserAttributes: [
          { Name: "email", Value: params.email },
          { Name: "email_verified", Value: "true" },
          { Name: "given_name", Value: params.firstName },
          { Name: "family_name", Value: params.lastName },
        ],
        DesiredDeliveryMediums: ["EMAIL"],
      }),
    );
    const username = result.User?.Username;
    if (!username) throw new Error("Cognito did not return a Username for the new admin user");
    return { username };
  },

  /**
   * Disable/enable an admin's Cognito account outright, so a suspended admin
   * cannot obtain a new token at all — not just a soft Postgres flag. Used by
   * PATCH /admin-users/:id/status alongside setting User.suspended.
   */
  async setUserEnabled(username: string, enabled: boolean): Promise<void> {
    const Command = enabled ? AdminEnableUserCommand : AdminDisableUserCommand;
    await client.send(new Command({ UserPoolId: env.COGNITO_USER_POOL_ID, Username: username }));
  },
};
