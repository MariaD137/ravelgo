import {
  CognitoIdentityProviderClient,
  AdminAddUserToGroupCommand,
} from "@aws-sdk/client-cognito-identity-provider";

// The AWS SDK v3 ships inside the Node.js 20 Lambda runtime, so there is
// nothing to bundle here.
const client = new CognitoIdentityProviderClient({});

/**
 * Cognito PostConfirmation trigger.
 *
 * Every self-signed-up user is placed in the "Rider" group so they can use the
 * rider role endpoints straight away. Rider is the only open-signup role by
 * design: Driver and Admin are elevated roles and are granted deliberately
 * (see scripts/set-role.sh), never automatically, so nobody can self-promote
 * to a driver or admin just by signing up.
 */
export const handler = async (event) => {
  // Fires for both sign-up confirmation and forgot-password confirmation.
  // Only assign a group on the initial sign-up.
  if (event.triggerSource !== "PostConfirmation_ConfirmSignUp") {
    return event;
  }

  await client.send(
    new AdminAddUserToGroupCommand({
      UserPoolId: event.userPoolId,
      Username: event.userName,
      GroupName: "Rider",
    }),
  );

  return event;
};
