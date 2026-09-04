import * as cdk from "aws-cdk-lib";
import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import * as rds from "aws-cdk-lib/aws-rds";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import type { Construct } from "constructs";

export interface ApiStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  dbInstance: rds.DatabaseInstance;
  dbSecurityGroup: ec2.SecurityGroup;
  documentsBucket: s3.Bucket;
  assetsBucket: s3.Bucket;
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

    const vpcConnector = new apprunner.CfnVpcConnector(this, "VpcConnector", {
      // Egress subnets (route to NAT) so the service can reach Stripe and the
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

    // Server-authoritative driver onboarding (P0 #2): the backend adds a user
    // to the Cognito "Driver" group on its own IAM role — the client never
    // touches group membership. Scope this to AdminAddUserToGroup on THIS pool
    // only (not a wildcard), so a compromised container can grant the Driver
    // role but cannot create/delete users, reset passwords, or touch any other
    // pool. Approving a driver to ACTIVE (the step that enables earning) is a
    // separate admin action, so this permission alone confers no ability to pay
    // out to a self-created account.
    const userPoolArn = cdk.Stack.of(this).formatArn({
      service: "cognito-idp",
      resource: "userpool",
      resourceName: props.cognitoUserPoolId,
    });
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ["cognito-idp:AdminAddUserToGroup"],
        resources: [userPoolArn],
      }),
    );

    const dbSecretArn = props.dbInstance.secret!.secretArn;

    // Placeholder values — CDK can't know your real Stripe keys, and they
    // shouldn't be plaintext CDK context/props anyway. Deploy creates this
    // secret with dummy values that will fail real Stripe calls until you
    // overwrite it once, post-deploy:
    //   aws secretsmanager put-secret-value --secret-id <StripeSecretArn output> \
    //     --secret-string '{"secretKey":"sk_live_...","webhookSecret":"whsec_..."}'
    // See ../../docs/admin-bootstrap.md for the same "one manual step,
    // documented" pattern used for the first Cognito Admin user.
    const stripeSecret = new secretsmanager.Secret(this, "StripeSecret", {
      description: "RavelGo Stripe keys — replace these placeholders post-deploy, see api-stack.ts",
      secretObjectValue: {
        // unsafePlainText is fine here specifically because these aren't
        // real secret material — they're placeholders meant to be
        // overwritten once, exactly like Cognito's admin bootstrap step.
        secretKey: cdk.SecretValue.unsafePlainText("sk_live_REPLACE_ME"),
        webhookSecret: cdk.SecretValue.unsafePlainText("whsec_REPLACE_ME"),
      },
    });
    stripeSecret.grantRead(instanceRole);

    // Same placeholder-then-overwrite pattern as the Stripe secret above: the
    // backend's Places/Geocoding proxy (src/routes/places.routes.ts) needs a
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

    if (deployService) {
    const service = new apprunner.CfnService(this, "BackendService", {
      serviceName: resourceName,
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
              { name: "ALLOWED_ORIGINS", value: props.allowedOrigins.join(",") },
            ],
            runtimeEnvironmentSecrets: [
              { name: "DB_USERNAME", value: `${dbSecretArn}:username::` },
              { name: "DB_PASSWORD", value: `${dbSecretArn}:password::` },
              { name: "STRIPE_SECRET_KEY", value: `${stripeSecret.secretArn}:secretKey::` },
              { name: "STRIPE_WEBHOOK_SECRET", value: `${stripeSecret.secretArn}:webhookSecret::` },
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

    new cdk.CfnOutput(this, "ServiceUrl", { value: `https://${service.attrServiceUrl}` });
    }

    new cdk.CfnOutput(this, "EcrRepositoryUri", { value: this.repository.repositoryUri });
    new cdk.CfnOutput(this, "StripeSecretArn", { value: stripeSecret.secretArn });
    new cdk.CfnOutput(this, "MapsSecretArn", { value: mapsSecret.secretArn });
  }
}
