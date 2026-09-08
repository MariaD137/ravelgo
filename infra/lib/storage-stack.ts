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

    // Vehicle photos, rental listing photos, avatars — and the built web apps
    // themselves — are served publicly through CloudFront (never expose the
    // bucket itself). Created first so the documents bucket below can scope its
    // upload CORS to this distribution's domain (the web apps' own origin).
    this.assetsBucket = new s3.Bucket(this, "AssetsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // IN-1: baseline WAF in front of the CDN — this distribution serves both
    // public assets (vehicle/rental photos) and the three built Flutter web
    // apps, so it's a real public entry point, not just a passive cache. WAF
    // requires a CLOUDFRONT-scope WebACL to be created in us-east-1
    // specifically (a CloudFront requirement, independent of which region
    // this stack itself deploys to — bin/infra.ts's default region already
    // is us-east-1). Same two managed rule groups + rate limit as the API's
    // own WAF (ApiStack) — see that stack for why each one is here.
    const cdnWebAcl = new wafv2.CfnWebACL(this, "AssetsWebAcl", {
      scope: "CLOUDFRONT",
      defaultAction: { allow: {} },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: "ravelgo-cdn-waf",
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
            metricName: "ravelgo-cdn-common",
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
            metricName: "ravelgo-cdn-sqli",
          },
        },
        {
          name: "RateLimit",
          priority: 3,
          action: { block: {} },
          statement: { rateBasedStatement: { limit: 2000, aggregateKeyType: "IP" } },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: "ravelgo-cdn-ratelimit",
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
      webAclId: cdnWebAcl.attrArn,
    });

    // Driver documents / Car Paddy uploads / support-ticket attachments:
    // private, accessed only via short-lived presigned URLs from the backend.
    this.documentsBucket = new s3.Bucket(this, "DocumentsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [{ noncurrentVersionExpiration: cdk.Duration.days(90) }],
      // The web apps upload documents by PUTting the file bytes straight to a
      // short-lived presigned URL (see backend POST /uploads/presign). A
      // browser PUT is a cross-origin request, so S3 must return CORS headers
      // or the browser blocks it — access is still gated by the presigned URL
      // (per-user key, 5-minute expiry). CORS is scoped to the CloudFront
      // domain the web apps are actually served from, rather than "*", so only
      // that origin's pages can send the bytes. (Add your custom domain here
      // too once one is attached to the distribution.)
      cors: [
        {
          allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: [`https://${this.assetsDistribution.distributionDomainName}`],
          allowedHeaders: ["*"],
          maxAge: 3000,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    new cdk.CfnOutput(this, "DocumentsBucketName", { value: this.documentsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsBucketName", { value: this.assetsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsDistributionDomain", { value: this.assetsDistribution.distributionDomainName });
  }
}
