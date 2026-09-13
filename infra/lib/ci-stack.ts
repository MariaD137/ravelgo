import * as cdk from "aws-cdk-lib";
import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import type { Construct } from "constructs";

export interface CiStackProps extends cdk.StackProps {
  repository: ecr.Repository;
  service: apprunner.CfnService;
  githubOrg: string;
  githubRepo: string;
  githubBranch: string;
  /**
   * "production" (default) creates a brand-new GitHub OIDC provider — AWS
   * allows only one per issuer URL per account, so every other environment
   * must import that same provider instead. Pass any other environment name
   * (e.g. "staging") to import it by its account-scoped ARN, which this
   * stack derives itself — it's deterministic, so no cross-stack reference
   * or manually-typed ARN is needed.
   */
  environmentName?: string;
  /**
   * When set, also grants upload access to the web-apps' assets bucket,
   * invalidation rights on its CloudFront distribution, and read-only
   * `cloudformation:DescribeStacks` on the named stacks — enough for CI to
   * discover the deployed API URL / Cognito IDs / bucket name / CloudFront
   * domain and publish Flutter web builds, in addition to deploying the
   * backend. Set for both environments — production's web apps deploy via
   * the manual .github/workflows/production-web-deploy.yml.
   */
  webAppsConfig?: {
    assetsBucket: s3.IBucket;
    assetsDistribution: cloudfront.IDistribution;
    /** CloudFormation stack names CI needs to read outputs from (Storage/Api/Auth). */
    configStackNames: string[];
  };
}

/**
 * Lets GitHub Actions push images and trigger deployments via OIDC — no
 * long-lived AWS access keys are ever stored as GitHub secrets. Instantiated
 * once per environment (production always; staging optionally — see
 * bin/infra.ts), each producing its own role scoped to that environment's
 * own resources, sharing one GitHub OIDC provider across all of them.
 */
export class CiStack extends cdk.Stack {
  public readonly deployRole: iam.Role;

  constructor(scope: Construct, id: string, props: CiStackProps) {
    super(scope, id, props);

    const environmentName = props.environmentName ?? "production";

    const provider =
      environmentName === "production"
        ? new iam.OpenIdConnectProvider(this, "GitHubOidcProvider", {
            url: "https://token.actions.githubusercontent.com",
            clientIds: ["sts.amazonaws.com"],
          })
        : iam.OpenIdConnectProvider.fromOpenIdConnectProviderArn(
            this,
            "GitHubOidcProvider",
            this.formatArn({
              service: "iam",
              region: "",
              resource: "oidc-provider",
              resourceName: "token.actions.githubusercontent.com",
            }),
          );

    // Two subject forms, because the token's `sub` claim depends on how the
    // workflow job is written: a plain job presents `...:ref:refs/heads/<branch>`,
    // but a job that declares `environment: <name>` presents
    // `...:environment:<name>` instead. Allowing only the branch form would
    // reject the real deploy job at AssumeRoleWithWebIdentity time.
    const subjects = [
      `repo:${props.githubOrg}/${props.githubRepo}:ref:refs/heads/${props.githubBranch}`,
      `repo:${props.githubOrg}/${props.githubRepo}:environment:${environmentName}`,
    ];

    const roleName =
      environmentName === "production" ? "ravelgo-github-actions-deploy" : `ravelgo-github-actions-deploy-${environmentName}`;

    this.deployRole = new iam.Role(this, "GitHubActionsDeployRole", {
      roleName,
      assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
        StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        StringLike: { "token.actions.githubusercontent.com:sub": subjects },
      }),
      description: `Assumed by GitHub Actions on ${props.githubOrg}/${props.githubRepo}@${props.githubBranch} to deploy ${environmentName}`,
      maxSessionDuration: cdk.Duration.hours(1),
    });

    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "EcrAuth",
        actions: ["ecr:GetAuthorizationToken"],
        resources: ["*"],
      }),
    );
    props.repository.grantPullPush(this.deployRole);
    // grantPullPush covers push/pull layer actions but not DescribeRepositories —
    // the staging workflow needs that separately to look up the repo's URI at
    // deploy time instead of hardcoding it as a GitHub variable (see
    // .github/workflows/staging-deploy.yml's "Discover the staging ECR repository" step).
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "EcrDescribeRepository",
        actions: ["ecr:DescribeRepositories"],
        resources: [props.repository.repositoryArn],
      }),
    );

    // ListServices, like ecr:DescribeRepositories and cloudfront:ListDistributions
    // above/below, has no resource-level permissions in IAM — the staging
    // workflow uses it to resolve the service ARN from its name rather than
    // hardcoding the ARN as a GitHub variable (see staging-deploy.yml's
    // "Trigger App Runner deployment" step).
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "AppRunnerListServices",
        actions: ["apprunner:ListServices"],
        resources: ["*"],
      }),
    );

    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "AppRunnerDeploy",
        // ListOperations lets the workflow wait for the rollout it started
        // and fail on FAILED/ROLLBACK_* (scripts/ci/apprunner-wait.sh)
        // instead of reporting success the moment the deploy is queued.
        actions: ["apprunner:StartDeployment", "apprunner:DescribeService", "apprunner:ListOperations"],
        resources: [props.service.attrServiceArn],
      }),
    );

    // Read-only. When apprunner-wait.sh sees FAILED/ROLLBACK_* it prints the
    // service's own recent CloudWatch logs — the only way to see *why* a
    // deployment failed to pass its health check (bad env/secret, crash on
    // boot, ...) directly in the workflow log, instead of a bare status name
    // that sends someone to hunt for console access. App Runner's log group
    // names embed a service ID this stack has no handle on
    // (/aws/apprunner/<name>/<id>/service|application), so this is scoped by
    // name prefix rather than pinned exactly.
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "AppRunnerLogsReadOnly",
        actions: ["logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"],
        resources: [
          this.formatArn({
            service: "logs",
            resource: "log-group",
            arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
            resourceName: `/aws/apprunner/${props.service.serviceName!}*:*`,
          }),
        ],
      }),
    );

    if (props.webAppsConfig) {
      props.webAppsConfig.assetsBucket.grantReadWrite(this.deployRole);

      // ListDistributions has no resource-level permissions in IAM (it's an
      // account-wide list call) — the workflow uses it to resolve the
      // distribution ID from its domain name, since that ID isn't exposed as
      // a CloudFormation stack output today.
      this.deployRole.addToPolicy(
        new iam.PolicyStatement({
          sid: "CloudFrontListDistributions",
          actions: ["cloudfront:ListDistributions"],
          resources: ["*"],
        }),
      );

      this.deployRole.addToPolicy(
        new iam.PolicyStatement({
          sid: "CloudFrontInvalidateWebApps",
          actions: ["cloudfront:CreateInvalidation"],
          resources: [
            this.formatArn({
              service: "cloudfront",
              region: "",
              resource: "distribution",
              resourceName: props.webAppsConfig.assetsDistribution.distributionId,
            }),
          ],
        }),
      );

      // Read-only: lets CI discover the API URL / Cognito IDs / bucket name /
      // CloudFront domain the same way scripts/host-web-staging.sh does,
      // instead of duplicating those values as separately-maintained GitHub
      // variables that could drift from the actual deployed stacks.
      this.deployRole.addToPolicy(
        new iam.PolicyStatement({
          sid: "ReadDeployedConfig",
          actions: ["cloudformation:DescribeStacks"],
          resources: props.webAppsConfig.configStackNames.map((name) =>
            this.formatArn({ service: "cloudformation", resource: "stack", resourceName: `${name}/*` }),
          ),
        }),
      );
    }

    new cdk.CfnOutput(this, "GitHubActionsDeployRoleArn", { value: this.deployRole.roleArn });
  }
}
