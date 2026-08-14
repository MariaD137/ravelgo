import * as cdk from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

/**
 * Private S3 bucket + CloudFront distribution for one Flutter web build
 * (admin_app / driver_app / user_app). The bucket is never public — only
 * CloudFront can read from it, via Origin Access Control.
 *
 * GitHub Actions (web-deploy.yml) owns getting files into the bucket —
 * `aws s3 sync build/web s3://<bucket>` on every push to main — this stack
 * only provisions the hosting, it never uploads anything itself.
 */
class WebAppHosting extends Construct {
  public readonly bucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.bucket = new s3.Bucket(this, "Bucket", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    this.distribution = new cloudfront.Distribution(this, "Distribution", {
      defaultRootObject: "index.html",
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.bucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      // Flutter web is a single-page app: a client-side route like
      // /trips/123 doesn't exist as an object in the bucket, so S3 answers
      // CloudFront with 403 (no ListBucket permission) or 404. Both get
      // rewritten to index.html so the Flutter router loads and takes over,
      // instead of the visitor seeing a raw S3 error page.
      errorResponses: [
        { httpStatus: 403, responseHttpStatus: 200, responsePagePath: "/index.html" },
        { httpStatus: 404, responseHttpStatus: 200, responsePagePath: "/index.html" },
      ],
    });
  }
}

export class WebStack extends cdk.Stack {
  public readonly adminApp: WebAppHosting;
  public readonly driverApp: WebAppHosting;
  public readonly userApp: WebAppHosting;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.adminApp = new WebAppHosting(this, "AdminApp");
    this.driverApp = new WebAppHosting(this, "DriverApp");
    this.userApp = new WebAppHosting(this, "UserApp");

    for (const [name, hosting] of [
      ["Admin", this.adminApp],
      ["Driver", this.driverApp],
      ["User", this.userApp],
    ] as const) {
      new cdk.CfnOutput(this, `${name}AppBucketName`, { value: hosting.bucket.bucketName });
      new cdk.CfnOutput(this, `${name}AppDistributionId`, { value: hosting.distribution.distributionId });
      new cdk.CfnOutput(this, `${name}AppUrl`, { value: `https://${hosting.distribution.distributionDomainName}` });
    }
  }
}
