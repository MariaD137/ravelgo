import * as cdk from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as guardduty from "aws-cdk-lib/aws-guardduty";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
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

    this.assetsDistribution = new cloudfront.Distribution(this, "AssetsDistribution", {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.assetsBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
    });

    // GuardDuty Malware Protection for S3: both buckets take arbitrary
    // user-uploaded files via the backend's presigned-upload endpoint
    // (driver documents/Car Paddy/support attachments here, vehicle/rental
    // photos and avatars in AssetsBucket) — scan every object on upload and
    // tag it with GDS status so the app can gate on it before treating a
    // file as safe to serve or forward.
    const malwareProtectionRole = new iam.Role(this, "MalwareProtectionRole", {
      assumedBy: new iam.ServicePrincipal("malware-protection-plan.guardduty.amazonaws.com", {
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
          ArnLike: { "aws:SourceArn": `arn:aws:guardduty:${this.region}:${this.account}:malware-protection-plan/*` },
        },
      }),
    });

    for (const bucket of [this.documentsBucket, this.assetsBucket]) {
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

    for (const bucket of [this.documentsBucket, this.assetsBucket]) {
      new guardduty.CfnMalwareProtectionPlan(this, `${bucket.node.id}MalwareProtectionPlan`, {
        role: malwareProtectionRole.roleArn,
        protectedResource: { s3Bucket: { bucketName: bucket.bucketName } },
        actions: { tagging: { status: "ENABLED" } },
      });
    }

    new cdk.CfnOutput(this, "DocumentsBucketName", { value: this.documentsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsBucketName", { value: this.assetsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsDistributionDomain", { value: this.assetsDistribution.distributionDomainName });
  }
}
