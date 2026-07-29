import * as cdk from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
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

    this.userPool = new cognito.UserPool(this, "UserPool", {
      userPoolName: envName === "production" ? "ravelgo-users" : `ravelgo-users-${envName}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
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
    });

    for (const groupName of ["Rider", "Driver", "Admin"]) {
      new cognito.CfnUserPoolGroup(this, `${groupName}Group`, {
        userPoolId: this.userPool.userPoolId,
        groupName,
        description: `${groupName} role`,
      });
    }

    new cdk.CfnOutput(this, "UserPoolId", { value: this.userPool.userPoolId });
    new cdk.CfnOutput(this, "UserPoolClientId", { value: this.userPoolClient.userPoolClientId });
  }
}
