import * as cdk from "aws-cdk-lib";
import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import type * as s3 from "aws-cdk-lib/aws-s3";
import type { Construct } from "constructs";

export interface CiStackWebApp {
  name: string;
  bucket: s3.Bucket;
  distribution: cloudfront.Distribution;
}

export interface CiStackProps extends cdk.StackProps {
  repository: ecr.Repository;
  service: apprunner.CfnService;
  webApps: CiStackWebApp[];
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

    const subject = `repo:${props.githubOrg}/${props.githubRepo}:ref:refs/heads/${props.githubBranch}`;

    const deployRole = new iam.Role(this, "GitHubActionsDeployRole", {
      roleName: "ravelgo-github-actions-deploy",
      assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
        StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        StringLike: { "token.actions.githubusercontent.com:sub": subject },
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

    // web-deploy.yml: `aws s3 sync build/web s3://<bucket>` + a CloudFront
    // invalidation, once per Flutter web app, on every push to main.
    for (const webApp of props.webApps) {
      webApp.bucket.grantReadWrite(deployRole);
      deployRole.addToPolicy(
        new iam.PolicyStatement({
          sid: `CloudFrontInvalidate${webApp.name}`,
          actions: ["cloudfront:CreateInvalidation"],
          resources: [
            `arn:aws:cloudfront::${cdk.Stack.of(this).account}:distribution/${webApp.distribution.distributionId}`,
          ],
        }),
      );
    }

    new cdk.CfnOutput(this, "GitHubActionsDeployRoleArn", { value: deployRole.roleArn });
  }
}
