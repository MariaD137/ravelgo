import {
  CognitoIdentityProviderClient,
  AdminAddUserToGroupCommand,
  AdminCreateUserCommand,
  AdminDisableUserCommand,
  AdminEnableUserCommand,
  AdminGetUserCommand,
  AdminResetUserPasswordCommand,
  MessageActionType,
  UserNotFoundException,
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

  /**
   * Live Cognito-side status for one admin: their account lifecycle state
   * (FORCE_CHANGE_PASSWORD means they haven't accepted the invitation yet —
   * surfaced to the Admin App as "Invited") and whether they have a
   * preferred MFA method set (TOTP is the only second factor this pool
   * offers — see infra/lib/auth-stack.ts). Nothing here is cached in
   * Postgres: Cognito is the single source of truth for both, so the
   * Admin Users list always reflects the real account state, never a value
   * that can drift out of sync.
   *
   * Returns null if the Cognito account itself is gone (e.g. deleted
   * directly in the AWS console) — the Postgres row can still exist and the
   * caller should render that as an anomaly rather than throwing.
   */
  async adminUserStatus(username: string): Promise<{ cognitoStatus: string; mfaEnabled: boolean } | null> {
    try {
      const result = await client.send(
        new AdminGetUserCommand({ UserPoolId: env.COGNITO_USER_POOL_ID, Username: username }),
      );
      return {
        cognitoStatus: result.UserStatus ?? "UNKNOWN",
        mfaEnabled: (result.UserMFASettingList?.length ?? 0) > 0,
      };
    } catch (err) {
      if (err instanceof UserNotFoundException) return null;
      throw err;
    }
  },

  /**
   * Re-send the invitation email for an admin who never completed their
   * first sign-in (still in FORCE_CHANGE_PASSWORD). Cognito rejects RESEND
   * for a user who has already set a real password, so the route handler
   * checks adminUserStatus() first and this never silently no-ops on an
   * already-active account.
   */
  async resendAdminInvitation(params: { email: string; firstName: string; lastName: string }): Promise<void> {
    await client.send(
      new AdminCreateUserCommand({
        UserPoolId: env.COGNITO_USER_POOL_ID,
        Username: params.email,
        UserAttributes: [
          { Name: "email", Value: params.email },
          { Name: "email_verified", Value: "true" },
          { Name: "given_name", Value: params.firstName },
          { Name: "family_name", Value: params.lastName },
        ],
        MessageAction: MessageActionType.RESEND,
        DesiredDeliveryMediums: ["EMAIL"],
      }),
    );
  },

  /**
   * Admin-initiated password reset: forces the target back into a
   * "must set a new password" state and emails them a reset code — the
   * same Cognito flow as a self-service "Forgot password?", just triggered
   * by a Super Admin instead of the account owner. Never returns, stores,
   * or logs the code or a password.
   */
  async adminResetUserPassword(username: string): Promise<void> {
    await client.send(new AdminResetUserPasswordCommand({ UserPoolId: env.COGNITO_USER_POOL_ID, Username: username }));
  },
};
