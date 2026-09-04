import * as path from "node:path";
import * as cdk from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import type { Construct } from "constructs";

export interface AuthStackProps extends cdk.StackProps {
  // Cognito pool *names* don't actually need to be unique (only the pool ID
  // does) — namespaced anyway so staging/production are distinguishable at
  // a glance in the Cognito console, not because it's required.
  envName?: string;
}

export class AuthStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;

  constructor(scope: Construct, id: string, props?: AuthStackProps) {
    super(scope, id, props);
    const envName = props?.envName ?? "production";

    // Email delivery (P0 #13). Cognito's built-in sender is capped at 50
    // emails/day account-wide, which silently breaks sign-up verification and
    // password reset at any real volume. When an SES sender is supplied (via
    // `-c sesFromEmail=no-reply@ravelgo.com`, optionally sesFromName /
    // sesReplyTo / sesRegion / sesVerifiedDomain) the pool sends through SES
    // instead, which has production sending limits.
    //
    // Manual prerequisites SES requires that CDK cannot do for you:
    //   1. Verify the sending identity (the domain, or the exact fromEmail) in
    //      SES in the sesRegion below.
    //   2. Move that SES account out of the sandbox (request production access)
    //      so it can email arbitrary recipients — in the sandbox only verified
    //      addresses receive mail.
    // Until sesFromEmail is set the pool falls back to the capped Cognito
    // sender and the MISSING-SES output below flags it.
    const sesFromEmail = this.node.tryGetContext("sesFromEmail") as string | undefined;
    const sesFromName = (this.node.tryGetContext("sesFromName") as string | undefined) ?? "RavelGo";
    const sesReplyTo = this.node.tryGetContext("sesReplyTo") as string | undefined;
    const sesRegion = (this.node.tryGetContext("sesRegion") as string | undefined) ?? this.region;
    const sesVerifiedDomain = this.node.tryGetContext("sesVerifiedDomain") as string | undefined;

    const email = sesFromEmail
      ? cognito.UserPoolEmail.withSES({
          fromEmail: sesFromEmail,
          fromName: sesFromName,
          replyTo: sesReplyTo,
          sesRegion,
          ...(sesVerifiedDomain ? { sesVerifiedDomain } : {}),
        })
      : undefined;

    this.userPool = new cognito.UserPool(this, "UserPool", {
      userPoolName: envName === "production" ? "ravelgo-users" : `ravelgo-users-${envName}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      ...(email ? { email } : {}),
      autoVerify: { email: true },
      standardAttributes: {
        givenName: { required: true, mutable: true },
        familyName: { required: true, mutable: true },
        phoneNumber: { required: false, mutable: true },
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // One client shared by the three Flutter apps; the group a user belongs
    // to (below) is what the backend uses to decide rider/driver/admin access,
    // not which app they happen to log in from.
    this.userPoolClient = this.userPool.addClient("MobileClient", {
      authFlows: { userPassword: true, userSrp: true },
      generateSecret: false,
      accessTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      // Return a uniform "incorrect username or password" for sign-in and a
      // uniform response for password reset regardless of whether the account
      // exists, so an attacker can't enumerate registered emails.
      preventUserExistenceErrors: true,
    });

    for (const groupName of ["Rider", "Driver", "Admin"]) {
      new cognito.CfnUserPoolGroup(this, `${groupName}Group`, {
        userPoolId: this.userPool.userPoolId,
        groupName,
        description: `${groupName} role`,
      });
    }

    // Auto-assign every new self-signup to the "Rider" group so riders can use
    // the app immediately. Driver/Admin stay manual (scripts/set-role.sh) — an
    // elevated role must never be grantable just by signing up.
    const postConfirmation = new lambda.Function(this, "PostConfirmation", {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: "index.handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "..", "lambda", "post-confirmation")),
      timeout: cdk.Duration.seconds(10),
      description: "Adds newly confirmed Cognito users to the Rider group",
    });

    // Scope to userpools in this account+region. Referencing the pool's ARN
    // directly here would create a pool <-> lambda circular dependency (the
    // pool references the trigger function, the function would reference the
    // pool), so a constructed wildcard ARN is used instead.
    postConfirmation.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["cognito-idp:AdminAddUserToGroup"],
        resources: [`arn:aws:cognito-idp:${this.region}:${this.account}:userpool/*`],
      }),
    );

    this.userPool.addTrigger(cognito.UserPoolOperation.POST_CONFIRMATION, postConfirmation);

    new cdk.CfnOutput(this, "UserPoolId", { value: this.userPool.userPoolId });
    new cdk.CfnOutput(this, "UserPoolClientId", { value: this.userPoolClient.userPoolClientId });
    new cdk.CfnOutput(this, "EmailSender", {
      value: sesFromEmail
        ? `SES <${sesFromEmail}> (region ${sesRegion}) — ensure the identity is verified and the account is out of the SES sandbox`
        : "COGNITO_DEFAULT — capped at 50 emails/day; set -c sesFromEmail=... to send via SES before launch",
    });
  }
}
