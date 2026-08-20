import * as cdk from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as guardduty from "aws-cdk-lib/aws-guardduty";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambdaBase from "aws-cdk-lib/aws-lambda";
import { S3EventSourceV2 } from "aws-cdk-lib/aws-lambda-event-sources";
import * as lambda from "aws-cdk-lib/aws-lambda-nodejs";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as wafv2 from "aws-cdk-lib/aws-wafv2";
import type { Construct } from "constructs";
import { join } from "node:path";

export class StorageStack extends cdk.Stack {
  public readonly documentsBucket: s3.Bucket;
  public readonly assetsBucket: s3.Bucket;
  public readonly pendingAssetsBucket: s3.Bucket;
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
      eventBridgeEnabled: true,
      lifecycleRules: [{ noncurrentVersionExpiration: cdk.Duration.days(90) }],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Vehicle photos, rental listing photos, avatars: served publicly through
    // CloudFront (never expose the bucket itself). Nothing uploads here
    // directly — see PendingAssetsBucket below for why.
    this.assetsBucket = new s3.Bucket(this, "AssetsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Uploads land here first, not in AssetsBucket. CloudFront's Origin
    // Access Control below is scoped to AssetsBucket only, so nothing
    // written here is ever publicly reachable — the upload-processor
    // Lambda is the only thing that can move an object out of this bucket
    // and into AssetsBucket, and only once it's passed magic-byte
    // validation. This closes the gap where an unvalidated upload would
    // otherwise be servable via CloudFront for however long GuardDuty/the
    // Lambda take to react: untrusted upload → validation → only then
    // publicly usable, never the other way around.
    this.pendingAssetsBucket = new s3.Bucket(this, "PendingAssetsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: true,
      eventBridgeEnabled: true,
      lifecycleRules: [
        { noncurrentVersionExpiration: cdk.Duration.days(90) },
        // Safety net: if the Lambda ever fails to run at all (not just
        // rejects the file), an object shouldn't sit here forever — it was
        // never promoted to AssetsBucket, so nothing user-facing depends
        // on it surviving.
        { expiration: cdk.Duration.days(7) },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const securityHeaders = new cloudfront.ResponseHeadersPolicy(this, "SecurityHeaders", {
      responseHeadersPolicyName: "RavelGo-SecurityHeaders",
      securityHeadersBehavior: {
        contentTypeOptions: { override: true },
        frameOptions: {
          frameOption: cloudfront.HeadersFrameOption.DENY,
          override: true,
        },
        strictTransportSecurity: {
          accessControlMaxAge: cdk.Duration.seconds(63072000),
          includeSubdomains: true,
          preload: true,
          override: true,
        },
        referrerPolicy: {
          referrerPolicy: cloudfront.HeadersReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN,
          override: true,
        },
      },
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
        responseHeadersPolicy: securityHeaders,
      },
      webAclId: assetsWebAcl.attrArn,
    });

    // GuardDuty Malware Protection for S3: all three buckets take
    // arbitrary user-uploaded files, directly or (for assets) via the
    // staging bucket — scan every object on upload and tag it with GDS
    // status. This runs alongside, not instead of, the upload-processor
    // Lambda's own magic-byte/EXIF validation below: GuardDuty catches
    // known malware signatures the Lambda's type-allowlist check doesn't
    // attempt to, the Lambda enforces the type allowlist and the
    // promote-on-approve gate GuardDuty alone doesn't provide.
    const malwareProtectionRole = new iam.Role(this, "MalwareProtectionRole", {
      assumedBy: new iam.ServicePrincipal("malware-protection-plan.guardduty.amazonaws.com", {
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
          ArnLike: { "aws:SourceArn": `arn:aws:guardduty:${this.region}:${this.account}:malware-protection-plan/*` },
        },
      }),
    });

    for (const bucket of [this.documentsBucket, this.pendingAssetsBucket]) {
      malwareProtectionRole.addToPolicy(
        new iam.PolicyStatement({
          sid: `Scan${bucket.node.id}`,
          actions: ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"],
          resources: [`${bucket.bucketArn}/*`],
        }),
      );
      malwareProtectionRole.addToPolicy(
        new iam.PolicyStatement({
          sid: `Tag${bucket.node.id}`,
          actions: [
            "s3:PutObjectTagging",
            "s3:GetObjectTagging",
            "s3:PutObjectVersionTagging",
            "s3:GetObjectVersionTagging",
          ],
          resources: [`${bucket.bucketArn}/*`],
        }),
      );
      malwareProtectionRole.addToPolicy(
        new iam.PolicyStatement({
          sid: `Bucket${bucket.node.id}`,
          actions: ["s3:ListBucket", "s3:GetBucketNotification", "s3:PutBucketNotification"],
          resources: [bucket.bucketArn],
        }),
      );
    }

    // GuardDuty manages a dedicated EventBridge rule per protected bucket
    // (named DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*) to receive
    // S3 object-created notifications — needs its own narrowly-scoped grant.
    malwareProtectionRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "ManageGuardDutyEventBridgeRule",
        actions: ["events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets"],
        resources: [`arn:aws:events:${this.region}:${this.account}:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*`],
      }),
    );
    malwareProtectionRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "DescribeGuardDutyEventBridgeRule",
        actions: ["events:DescribeRule", "events:ListTargetsByRule"],
        resources: [`arn:aws:events:${this.region}:${this.account}:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*`],
      }),
    );

    for (const bucket of [this.documentsBucket, this.pendingAssetsBucket]) {
      new guardduty.CfnMalwareProtectionPlan(this, `${bucket.node.id}MalwareProtectionPlan`, {
        role: malwareProtectionRole.roleArn,
        protectedResource: { s3Bucket: { bucketName: bucket.bucketName } },
        actions: { tagging: { status: "ENABLED" } },
      });
    }

    // Real MIME/type validation (magic bytes, not the client-declared
    // Content-Type header) and EXIF stripping, triggered on every S3
    // "Object Created" event for either bucket. For DocumentsBucket
    // (always private) it validates and strips in place. For
    // PendingAssetsBucket it does the same, then — and only on success —
    // copies the object into AssetsBucket (the one CloudFront serves) and
    // removes it from the staging bucket; a rejected file is just deleted
    // from PendingAssetsBucket and never reaches AssetsBucket at all.
    const uploadProcessor = new lambda.NodejsFunction(this, "UploadProcessorFunction", {
      entry: join(__dirname, "..", "lambda", "upload-processor", "index.ts"),
      handler: "handler",
      runtime: lambdaBase.Runtime.NODEJS_22_X,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: { externalModules: ["@aws-sdk/client-s3"] },
      environment: {
        DOCUMENTS_BUCKET: this.documentsBucket.bucketName,
        PENDING_ASSETS_BUCKET: this.pendingAssetsBucket.bucketName,
        ASSETS_BUCKET: this.assetsBucket.bucketName,
      },
    });

    this.documentsBucket.grantReadWrite(uploadProcessor);
    this.documentsBucket.grantDelete(uploadProcessor);
    this.pendingAssetsBucket.grantReadWrite(uploadProcessor);
    this.pendingAssetsBucket.grantDelete(uploadProcessor);
    this.assetsBucket.grantWrite(uploadProcessor);

    uploadProcessor.addEventSource(
      new S3EventSourceV2(this.documentsBucket, { events: [s3.EventType.OBJECT_CREATED] }),
    );
    uploadProcessor.addEventSource(
      new S3EventSourceV2(this.pendingAssetsBucket, { events: [s3.EventType.OBJECT_CREATED] }),
    );

    new cdk.CfnOutput(this, "DocumentsBucketName", { value: this.documentsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsBucketName", { value: this.assetsBucket.bucketName });
    new cdk.CfnOutput(this, "PendingAssetsBucketName", { value: this.pendingAssetsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsDistributionDomain", { value: this.assetsDistribution.distributionDomainName });
  }
}
