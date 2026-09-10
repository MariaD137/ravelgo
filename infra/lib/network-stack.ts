import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import type { Construct } from "constructs";

export interface NetworkStackProps extends cdk.StackProps {
  // Production runs two NAT gateways (one per AZ) for high availability;
  // staging/dev run a single NAT to keep cost down. Defaults to production.
  envName?: string;
}

export class NetworkStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props?: NetworkStackProps) {
    super(scope, id, props);
    const isProduction = (props?.envName ?? "production") === "production";

    // Three subnet tiers, each with a distinct job:
    //  - public:   holds the NAT gateway(s) and nothing else.
    //  - egress:   App Runner's VPC connector lives here; it routes OUTBOUND
    //              traffic through the NAT so the backend can reach Paystack and
    //              the Cognito JWKS endpoint (needed to verify every token),
    //              while still accepting no inbound traffic from the internet.
    //  - isolated: the database — no route to the internet at all, reachable
    //              only from inside the VPC.
    //
    // The earlier design used isolated-only subnets with no NAT, which meant
    // the App Runner service could reach RDS but could NOT reach Paystack or
    // Cognito — breaking payments and authentication. This is that fix.
    this.vpc = new ec2.Vpc(this, "RavelGoVpc", {
      maxAzs: 2,
      natGateways: isProduction ? 2 : 1,
      subnetConfiguration: [
        { name: "public", subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
        { name: "egress", subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
        { name: "isolated", subnetType: ec2.SubnetType.PRIVATE_ISOLATED, cidrMask: 24 },
      ],
    });

    // Free S3 access that does not traverse (and get billed by) the NAT
    // gateway — presigned-URL signing and any bucket I/O stay on AWS's network.
    this.vpc.addGatewayEndpoint("S3Endpoint", {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });
  }
}
