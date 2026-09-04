import * as cdk from "aws-cdk-lib";
import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import type { Construct } from "constructs";

export interface CiStackProps extends cdk.StackProps {
  repository: ecr.Repository;
  service: apprunner.CfnService;
  githubOrg: string;
  githubRepo: string;
  githubBranch: string;
}

/**
 * Lets GitHub Actions push images and trigger deployments via OIDC —
 * no long-lived AWS access keys are ever stored as GitHub secrets.
 */
export class CiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: CiStackProps) {
    super(scope, id, props);

    const provider = new iam.OpenIdConnectProvider(this, "GitHubOidcProvider", {
      url: "https://token.actions.githubusercontent.com",
      clientIds: ["sts.amazonaws.com"],
    });

    // Two subject forms, because the token's `sub` claim depends on how the
    // workflow job is written: a plain job presents `...:ref:refs/heads/<branch>`,
    // but a job that declares `environment: production` (as
    // backend-deploy.yml does) presents `...:environment:production` instead.
    // Allowing only the branch form would reject the real deploy job at
    // AssumeRoleWithWebIdentity time.
    const subjects = [
      `repo:${props.githubOrg}/${props.githubRepo}:ref:refs/heads/${props.githubBranch}`,
      `repo:${props.githubOrg}/${props.githubRepo}:environment:production`,
    ];

    const deployRole = new iam.Role(this, "GitHubActionsDeployRole", {
      roleName: "ravelgo-github-actions-deploy",
      assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
        StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        StringLike: { "token.actions.githubusercontent.com:sub": subjects },
      }),
      description: `Assumed by GitHub Actions on ${props.githubOrg}/${props.githubRepo}@${props.githubBranch} to deploy the backend`,
      maxSessionDuration: cdk.Duration.hours(1),
    });

    deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "EcrAuth",
        actions: ["ecr:GetAuthorizationToken"],
        resources: ["*"],
      }),
    );
    props.repository.grantPullPush(deployRole);

    deployRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "AppRunnerDeploy",
        actions: ["apprunner:StartDeployment", "apprunner:DescribeService"],
        resources: [props.service.attrServiceArn],
      }),
    );

    new cdk.CfnOutput(this, "GitHubActionsDeployRoleArn", { value: deployRole.roleArn });
  }
}
