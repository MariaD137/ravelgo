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
   * backend. Omitted for production today (its web apps aren't auto-deployed
   * by CI yet).
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

    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "AppRunnerDeploy",
        actions: ["apprunner:StartDeployment", "apprunner:DescribeService"],
        resources: [props.service.attrServiceArn],
      }),
    );

    if (props.webAppsConfig) {
      props.webAppsConfig.assetsBucket.grantReadWrite(this.deployRole);

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
