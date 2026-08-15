import * as cdk from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as wafv2 from "aws-cdk-lib/aws-wafv2";
import type { Construct } from "constructs";

export class StorageStack extends cdk.Stack {
  public readonly documentsBucket: s3.Bucket;
  public readonly assetsBucket: s3.Bucket;
  public readonly assetsDistribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Driver documents / Car Paddy uploads / support-ticket attachments:
    // private, accessed only via short-lived presigned URLs from the backend.
    this.documentsBucket = new s3.Bucket(this, "DocumentsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [{ noncurrentVersionExpiration: cdk.Duration.days(90) }],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Vehicle photos, rental listing photos, avatars: served publicly through
    // CloudFront (never expose the bucket itself).
    this.assetsBucket = new s3.Bucket(this, "AssetsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // WAFv2 WebACLs scoped to CLOUDFRONT only exist in the us-east-1 API
    // endpoint, regardless of where this stack itself deploys — CloudFront
    // is a global service, but its WAF integration is not. bin/infra.ts
    // defaults env.region to "us-east-1", so this holds for a plain `cdk
    // deploy`; overriding CDK_DEFAULT_REGION away from us-east-1 would break
    // this WebACL, the same way it would break the distribution itself.
    const assetsWebAcl = new wafv2.CfnWebACL(this, "AssetsWebAcl", {
      scope: "CLOUDFRONT",
      defaultAction: { allow: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: "AssetsWebAclDefault",
        sampledRequestsEnabled: true,
      },
      rules: [
        {
          name: "AWS-AWSManagedRulesCommonRuleSet",
          priority: 0,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: { vendorName: "AWS", name: "AWSManagedRulesCommonRuleSet" },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: "AssetsWebAclCommonRuleSet",
            sampledRequestsEnabled: true,
          },
        },
        {
          name: "AWS-AWSManagedRulesKnownBadInputsRuleSet",
          priority: 1,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: { vendorName: "AWS", name: "AWSManagedRulesKnownBadInputsRuleSet" },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: "AssetsWebAclKnownBadInputs",
            sampledRequestsEnabled: true,
          },
        },
        {
          name: "AWS-AWSManagedRulesAmazonIpReputationList",
          priority: 2,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: { vendorName: "AWS", name: "AWSManagedRulesAmazonIpReputationList" },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: "AssetsWebAclIpReputationList",
            sampledRequestsEnabled: true,
          },
        },
        // Static assets (photos/avatars) are read repeatedly by legitimate
        // page loads, so this is a scraping/DDoS backstop, not a tight
        // per-user quota — 2000 req/5min per IP, well above normal browsing.
        {
          name: "RateLimitPerIp",
          priority: 3,
          action: { block: {} },
          statement: {
            rateBasedStatement: { limit: 2000, aggregateKeyType: "IP" },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: "AssetsWebAclRateLimit",
            sampledRequestsEnabled: true,
          },
        },
      ],
    });

    this.assetsDistribution = new cloudfront.Distribution(this, "AssetsDistribution", {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.assetsBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      webAclId: assetsWebAcl.attrArn,
    });

    new cdk.CfnOutput(this, "DocumentsBucketName", { value: this.documentsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsBucketName", { value: this.assetsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsDistributionDomain", { value: this.assetsDistribution.distributionDomainName });
  }
}
