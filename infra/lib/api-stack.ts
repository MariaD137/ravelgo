import * as cdk from "aws-cdk-lib";
import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import * as rds from "aws-cdk-lib/aws-rds";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as wafv2 from "aws-cdk-lib/aws-wafv2";
import type { Construct } from "constructs";

export interface ApiStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  dbInstance: rds.DatabaseInstance;
  dbSecurityGroup: ec2.SecurityGroup;
  documentsBucket: s3.Bucket;
  assetsBucket: s3.Bucket;
  // The assets bucket's CloudFront domain (StorageStack's AssetsDistribution)
  // — lets the backend build a public URL for something stored there (e.g. a
  // vehicle photo) without signing a GET, since that bucket is meant to be
  // publicly viewable in the first place.
  assetsCdnDomain: string;
  cognitoUserPoolId: string;
  cognitoUserPoolClientId: string;
  // Comma-joined into ALLOWED_ORIGINS — env.ts throws at container boot in
  // production if this ends up empty, so there's no silent-failure mode:
  // forgetting to pass this breaks the deploy loudly instead of quietly
  // leaving CORS wide open.
  allowedOrigins: string[];
  // ECR repo names and App Runner service names *are* unique per
  // account+region, unlike Cognito pool names — this suffix is what makes
  // IN-06's staging deploy possible at all in the same AWS account as
  // production, not just cosmetic.
  envName?: string;
  // The Pinpoint Application device push is sent through (AuthStack.
  // pinpointApplicationId — see that stack for why it lives there). Always
  // passed (the resource always exists), but push only actually delivers
  // once its GCM/APNS channels are enabled with a real FCM/APNs credential —
  // see the comment further below for the exact command. Until then this
  // backend simply never sends a push; every in-app notification still
  // persists and lists normally either way.
  pinpointApplicationId: string;
  // First-deploy bootstrap: an App Runner service pointed at an ECR image
  // tag that doesn't exist yet fails to stabilize and rolls the whole stack
  // back. On a brand-new environment there's no image until *after* the ECR
  // repo this stack creates exists to push to. Setting this false deploys
  // the repo (+ secret + roles) without the service, so a first image can be
  // built and pushed; a second deploy with it true (the default) then brings
  // the service up against an image that already exists. Existing
  // environments and `cdk deploy --all` are unaffected — it defaults to true.
  deployService?: boolean;
}

export class ApiStack extends cdk.Stack {
  public readonly repository: ecr.Repository;
  // Undefined only during a first-deploy bootstrap (deployService: false),
  // when the ECR repo is created ahead of the first image. Every normal
  // deploy creates it.
  public readonly service?: apprunner.CfnService;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);
    const envName = props.envName ?? "production";
    const deployService = props.deployService ?? true;
    const resourceName = envName === "production" ? "ravelgo-backend" : `ravelgo-backend-${envName}`;

    this.repository = new ecr.Repository(this, "BackendRepository", {
      repositoryName: resourceName,
      imageScanOnPush: true,
      lifecycleRules: [{ maxImageCount: 20 }],
    });

    // Lets App Runner's compute reach the RDS instance, which lives in
    // isolated subnets with no route to the internet.
    const connectorSecurityGroup = new ec2.SecurityGroup(this, "ConnectorSecurityGroup", {
      vpc: props.vpc,
      description: "App Runner VPC connector to RDS",
      allowAllOutbound: true,
    });

    // A standalone ingress-rule resource (rather than dbSecurityGroup.addIngressRule)
    // so the rule lives in this stack instead of mutating DataStack's security
    // group — mutating it there would create a dependency cycle between the two.
    new ec2.CfnSecurityGroupIngress(this, "DbIngressFromConnector", {
      groupId: props.dbSecurityGroup.securityGroupId,
      sourceSecurityGroupId: connectorSecurityGroup.securityGroupId,
      ipProtocol: "tcp",
      fromPort: 5432,
      toPort: 5432,
      description: "From App Runner VPC connector",
    });

    // P2 #5 (driver-location architecture): the real-time layer
    // (src/realtime/hub.ts) is deliberately in-memory, single-instance —
    // see docs/realtime-architecture.md's "trade-off, on the record". That
    // was previously only an assumption: with no AutoScalingConfiguration
    // attached, App Runner falls back to its account default (MinSize 1,
    // MaxSize 25), which COULD silently scale this service to more than one
    // instance under real concurrent load, quietly breaking driver-location
    // visibility for whichever riders/admins land on a different instance —
    // with no error, no alarm, just an intermittently wrong map. Pinning
    // MaxSize to 1 here turns "we don't currently need more than one
    // instance" into an enforced guarantee instead of a hope, at zero
    // additional runtime cost (an AutoScalingConfiguration is a free
    // control-plane resource). The concrete signal to revisit this (raise
    // MaxSize and move the realtime hub to a shared store) is this service
    // genuinely needing to scale out under real load — see
    // docs/realtime-architecture.md.
    const autoScaling = new apprunner.CfnAutoScalingConfiguration(this, "SingleInstanceAutoScaling", {
      autoScalingConfigurationName: resourceName,
      maxSize: 1,
      minSize: 1,
    });

    const vpcConnector = new apprunner.CfnVpcConnector(this, "VpcConnector", {
      // Egress subnets (route to NAT) so the service can reach Paystack and the
      // Cognito JWKS endpoint; it still reaches RDS in the isolated subnets
      // over the same VPC. Isolated subnets alone would leave it with no
      // internet path and break payments + auth.
      subnets: props.vpc.selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }).subnetIds,
      securityGroups: [connectorSecurityGroup.securityGroupId],
    });

    const accessRole = new iam.Role(this, "AppRunnerAccessRole", {
      assumedBy: new iam.ServicePrincipal("build.apprunner.amazonaws.com"),
      description: "Lets App Runner pull the backend image from ECR",
    });
    this.repository.grantPull(accessRole);

    const instanceRole = new iam.Role(this, "AppRunnerInstanceRole", {
      assumedBy: new iam.ServicePrincipal("tasks.apprunner.amazonaws.com"),
      description: "Runtime permissions for the running backend container",
    });
    props.dbInstance.secret?.grantRead(instanceRole);
    props.documentsBucket.grantReadWrite(instanceRole);
    props.assetsBucket.grantReadWrite(instanceRole);

    // Push notifications (AWS Pinpoint): lets the backend send a message
    // directly to a device's raw token — see services/push.ts, which never
    // needs a pre-created "endpoint" resource, unlike SNS Mobile Push.
    // Scoped to exactly this one Pinpoint application, and harmless to grant
    // even before its GCM/APNS channels are configured with a real
    // credential — see the pinpointApplicationId comment above for why this
    // feature stays fully optional and never blocks a deploy.
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ["mobiletargeting:SendMessages"],
        resources: [
          cdk.Stack.of(this).formatArn({
            service: "mobiletargeting",
            resource: `apps/${props.pinpointApplicationId}/messages`,
          }),
        ],
      }),
    );

    // Server-authoritative user management on THIS pool only (never a
    // wildcard), so a compromised container can manage users in this one pool
    // but cannot touch any other pool. Two groups of actions:
    //
    //   1. Driver onboarding (P0 #2): the backend adds a user to the Cognito
    //      "Driver" group on its own IAM role — the client never touches group
    //      membership. Approving a driver to ACTIVE (the step that enables
    //      earning) is a separate admin action, so AdminAddUserToGroup alone
    //      confers no ability to pay out to a self-created account.
    //
    //   2. Admin-user lifecycle + admin sign-in (see services/cognito.ts and
    //      routes/admin-users.routes.ts). AdminGetUser in particular is called
    //      on EVERY admin sign-in (GET /admin-users/me -> adminUserStatus reads
    //      the account's live status/MFA) and on every mutating admin action
    //      (isAdminMfaEnrolled). Without it the instance role could only add to
    //      groups, so adminUserStatus() threw AccessDenied at runtime — which
    //      only UserNotFoundException is caught for, so it surfaced as an
    //      uncaught 500 ("could not verify your admin account") that blocked
    //      admin login entirely. These are all admin-only, pool-scoped
    //      operations the backend already gates behind requireAdminPermission.
    const userPoolArn = cdk.Stack.of(this).formatArn({
      service: "cognito-idp",
      resource: "userpool",
      resourceName: props.cognitoUserPoolId,
    });
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminResetUserPassword",
          "cognito-idp:AdminUserGlobalSignOut",
        ],
        resources: [userPoolArn],
      }),
    );

    const dbSecretArn = props.dbInstance.secret!.secretArn;

    // Placeholder value — CDK can't know your real Paystack secret key, and
    // it shouldn't be plaintext CDK context/props anyway. Deploy creates this
    // secret with a dummy value that will fail real Paystack calls until you
    // overwrite it once, post-deploy:
    //   aws secretsmanager put-secret-value --secret-id <PaystackSecretArn output> \
    //     --secret-string '{"secretKey":"sk_live_..."}'
    // Only one field — unlike the removed Stripe integration, Paystack signs
    // webhooks with this same secret key rather than a separate one.
    // See ../../docs/admin-bootstrap.md for the same "one manual step,
    // documented" pattern used for the first Cognito Admin user.
    const paystackSecret = new secretsmanager.Secret(this, "PaystackSecret", {
      description: "RavelGo Paystack secret key — replace this placeholder post-deploy, see api-stack.ts",
      secretObjectValue: {
        // unsafePlainText is fine here specifically because this isn't real
        // secret material — a placeholder meant to be overwritten once,
        // exactly like Cognito's admin bootstrap step.
        secretKey: cdk.SecretValue.unsafePlainText("sk_live_REPLACE_ME"),
      },
    });
    paystackSecret.grantRead(instanceRole);

    // Same placeholder-then-overwrite pattern as the Paystack secret above:
    // the backend's Places/Geocoding proxy (src/routes/places.routes.ts) needs a
    // server-side Google Maps Platform key, which CDK can't know and shouldn't
    // carry in plaintext context. Deploy lays down a placeholder that makes the
    // proxy return a clear 5xx (never a silent failure) until you overwrite it:
    //   aws secretsmanager put-secret-value --secret-id <MapsSecretArn output> \
    //     --secret-string '{"serverKey":"AIza..."}'
    // Restrict the real key to this backend's egress IP + the Places and
    // Geocoding APIs only — unlike the browser Maps-JS key, it is never shipped
    // to a client.
    const mapsSecret = new secretsmanager.Secret(this, "MapsSecret", {
      description: "RavelGo Google Maps server key — replace this placeholder post-deploy, see api-stack.ts",
      secretObjectValue: {
        serverKey: cdk.SecretValue.unsafePlainText("AIza_REPLACE_ME"),
      },
    });
    mapsSecret.grantRead(instanceRole);

    // Push notifications, same "CDK can't know your real credentials, one
    // manual step, documented" pattern as the Stripe/Maps secrets above —
    // except this one is optional even in production. The Pinpoint
    // Application itself always exists (AuthStack.pinpointApplicationId);
    // what's missing until you do this is a real credential on its GCM/APNS
    // channels:
    //   aws pinpoint update-gcm-channel --application-id <id> \
    //     --gcm-channel-request ApiKey=<FCM server key>,Enabled=true
    //   aws pinpoint update-apns-channel --application-id <id> \
    //     --apns-channel-request BundleId=<ios bundle id>,TeamId=<team id>,TokenKey=<APNs .p8 key>,TokenKeyId=<key id>,Enabled=true
    // Until then, PINPOINT_APPLICATION_ID is still set below (SendMessages
    // against channels with no credential just fails per-address, the same
    // "in-app notification unaffected either way" outcome as if it were
    // unset — see services/push.ts's own error handling).
    if (deployService) {
    const service = new apprunner.CfnService(this, "BackendService", {
      serviceName: resourceName,
      autoScalingConfigurationArn: autoScaling.attrAutoScalingConfigurationArn,
      sourceConfiguration: {
        autoDeploymentsEnabled: true,
        authenticationConfiguration: { accessRoleArn: accessRole.roleArn },
        imageRepository: {
          imageRepositoryType: "ECR",
          imageIdentifier: `${this.repository.repositoryUri}:latest`,
          imageConfiguration: {
            port: "8080",
            runtimeEnvironmentVariables: [
              { name: "NODE_ENV", value: "production" },
              { name: "AWS_REGION", value: this.region },
              { name: "DB_HOST", value: props.dbInstance.instanceEndpoint.hostname },
              { name: "DB_PORT", value: props.dbInstance.instanceEndpoint.port.toString() },
              { name: "DB_NAME", value: "ravelgo" },
              { name: "COGNITO_USER_POOL_ID", value: props.cognitoUserPoolId },
              { name: "COGNITO_CLIENT_ID", value: props.cognitoUserPoolClientId },
              { name: "DOCUMENTS_BUCKET", value: props.documentsBucket.bucketName },
              { name: "ASSETS_BUCKET", value: props.assetsBucket.bucketName },
              { name: "ASSETS_CDN_DOMAIN", value: props.assetsCdnDomain },
              { name: "ALLOWED_ORIGINS", value: props.allowedOrigins.join(",") },
              // Not a secret — an application ID identifies a resource, it
              // doesn't authenticate anything.
              { name: "PINPOINT_APPLICATION_ID", value: props.pinpointApplicationId },
            ],
            runtimeEnvironmentSecrets: [
              { name: "DB_USERNAME", value: `${dbSecretArn}:username::` },
              { name: "DB_PASSWORD", value: `${dbSecretArn}:password::` },
              { name: "PAYSTACK_SECRET_KEY", value: `${paystackSecret.secretArn}:secretKey::` },
              { name: "GOOGLE_MAPS_SERVER_KEY", value: `${mapsSecret.secretArn}:serverKey::` },
            ],
          },
        },
      },
      instanceConfiguration: {
        cpu: "1024",
        memory: "2048",
        instanceRoleArn: instanceRole.roleArn,
      },
      networkConfiguration: {
        egressConfiguration: {
          egressType: "VPC",
          vpcConnectorArn: vpcConnector.attrVpcConnectorArn,
        },
      },
      healthCheckConfiguration: {
        protocol: "HTTP",
        path: "/health",
        interval: 10,
        timeout: 5,
        healthyThreshold: 1,
        unhealthyThreshold: 5,
      },
    });
    this.service = service;

    // IN-1: baseline WAF in front of the API. REGIONAL scope (not
    // CLOUDFRONT — that's StorageStack's job for the CDN in front of the web
    // apps) — App Runner is one of the resource types AWS WAF can attach to
    // directly, same as an ALB. Two AWS-managed rule groups cover the classes
    // of exploit an MVP backend most plausibly meets (generic web exploits,
    // SQL injection); the rate-based rule is a blunt but real backstop
    // against a single source hammering the API, independent of and in
    // addition to the app's own per-route rate limiters (middleware/rate-limit.ts),
    // which only throttle specific expensive endpoints, not every request.
    const webAcl = new wafv2.CfnWebACL(this, "ApiWebAcl", {
      scope: "REGIONAL",
      defaultAction: { allow: {} },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: `${resourceName}-waf`,
      },
      rules: [
        {
          name: "AWS-AWSManagedRulesCommonRuleSet",
          priority: 1,
          overrideAction: { none: {} },
          statement: { managedRuleGroupStatement: { vendorName: "AWS", name: "AWSManagedRulesCommonRuleSet" } },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: `${resourceName}-common`,
          },
        },
        {
          name: "AWS-AWSManagedRulesSQLiRuleSet",
          priority: 2,
          overrideAction: { none: {} },
          statement: { managedRuleGroupStatement: { vendorName: "AWS", name: "AWSManagedRulesSQLiRuleSet" } },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: `${resourceName}-sqli`,
          },
        },
        {
          // Per-IP request ceiling over WAF's 5-minute evaluation window.
          // 2000 comfortably covers a real user/app polling normally; a
          // single source blowing past it is blocked until its rate drops.
          name: "RateLimit",
          priority: 3,
          action: { block: {} },
          statement: { rateBasedStatement: { limit: 2000, aggregateKeyType: "IP" } },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: `${resourceName}-ratelimit`,
          },
        },
      ],
    });
    new wafv2.CfnWebACLAssociation(this, "ApiWebAclAssociation", {
      resourceArn: service.attrServiceArn,
      webAclArn: webAcl.attrArn,
    });

    new cdk.CfnOutput(this, "ServiceUrl", { value: `https://${service.attrServiceUrl}` });
    }

    new cdk.CfnOutput(this, "EcrRepositoryUri", { value: this.repository.repositoryUri });
    new cdk.CfnOutput(this, "PaystackSecretArn", { value: paystackSecret.secretArn });
    new cdk.CfnOutput(this, "MapsSecretArn", { value: mapsSecret.secretArn });
  }
}
