import * as path from "node:path";
import * as cdk from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as events from "aws-cdk-lib/aws-events";
import * as eventsTargets from "aws-cdk-lib/aws-events-targets";
import * as guardduty from "aws-cdk-lib/aws-guardduty";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import { NodejsFunction, OutputFormat } from "aws-cdk-lib/aws-lambda-nodejs";
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
      eventBridgeEnabled: true,
      lifecycleRules: [{ noncurrentVersionExpiration: cdk.Duration.days(90) }],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Vehicle photos, rental listing photos, avatars: served publicly through
    // CloudFront (never expose the bucket itself).
    this.assetsBucket = new s3.Bucket(this, "AssetsBucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      eventBridgeEnabled: true,
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
          // Both buckets already declare eventBridgeEnabled below, so this
          // notification-config grant is a no-op in steady state — kept as
          // defense-in-depth in case GuardDuty needs to (re)assert it.
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

    // Post-upload validation: GuardDuty above catches malware, but a client
    // can still upload arbitrary bytes under a false Content-Type (the
    // presigned-upload endpoint only checks the declared header, not the
    // real file). This Lambda re-derives the actual type from magic bytes
    // after the object lands, deletes anything that doesn't match an
    // allow-listed signature for its bucket, and strips EXIF/XMP metadata
    // (GPS coordinates, camera serials) from images — most importantly in
    // AssetsBucket, which serves straight to the public internet.
    const uploadProcessor = new NodejsFunction(this, "UploadProcessorFunction", {
      entry: path.join(__dirname, "..", "lambda", "upload-processor", "index.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 512,
      timeout: cdk.Duration.seconds(30),
      bundling: { format: OutputFormat.ESM, minify: true },
      environment: {
        DOCUMENTS_BUCKET_NAME: this.documentsBucket.bucketName,
        ASSETS_BUCKET_NAME: this.assetsBucket.bucketName,
      },
    });
    this.documentsBucket.grantReadWrite(uploadProcessor);
    this.documentsBucket.grantDelete(uploadProcessor);
    this.assetsBucket.grantReadWrite(uploadProcessor);
    this.assetsBucket.grantDelete(uploadProcessor);

    new events.Rule(this, "UploadProcessorTrigger", {
      eventPattern: {
        source: ["aws.s3"],
        detailType: ["Object Created"],
        detail: {
          bucket: { name: [this.documentsBucket.bucketName, this.assetsBucket.bucketName] },
        },
      },
      targets: [new eventsTargets.LambdaFunction(uploadProcessor)],
    });

    new cdk.CfnOutput(this, "DocumentsBucketName", { value: this.documentsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsBucketName", { value: this.assetsBucket.bucketName });
    new cdk.CfnOutput(this, "AssetsDistributionDomain", { value: this.assetsDistribution.distributionDomainName });
  }
}
