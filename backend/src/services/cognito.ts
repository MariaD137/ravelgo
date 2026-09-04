import {
  CognitoIdentityProviderClient,
  AdminAddUserToGroupCommand,
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
};
