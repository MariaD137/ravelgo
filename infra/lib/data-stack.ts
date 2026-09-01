import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as rds from "aws-cdk-lib/aws-rds";
import type { Construct } from "constructs";

export interface DataStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  // "production" gets a database that can't be torn down by accident;
  // staging/dev stay deletable so a throwaway environment can be cleaned up
  // fast. Defaults to production behaviour when unset (safest).
  envName?: string;
}

export class DataStack extends cdk.Stack {
  public readonly dbInstance: rds.DatabaseInstance;
  public readonly dbSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: DataStackProps) {
    super(scope, id, props);

    const isProduction = (props.envName ?? "production") === "production";

    this.dbSecurityGroup = new ec2.SecurityGroup(this, "DbSecurityGroup", {
      vpc: props.vpc,
      description: "RavelGo RDS Postgres access",
      allowAllOutbound: false,
    });

    // Start on a small single-AZ instance to keep MVP cost down. Switch to
    // Aurora Serverless v2 or a Multi-AZ instance once traffic/uptime needs
    // justify it — see infra/README.md.
    this.dbInstance = new rds.DatabaseInstance(this, "Database", {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16_4,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE4_GRAVITON, ec2.InstanceSize.MICRO),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      securityGroups: [this.dbSecurityGroup],
      credentials: rds.Credentials.fromGeneratedSecret("ravelgo_admin"),
      databaseName: "ravelgo",
      allocatedStorage: 20,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      multiAz: false,
      backupRetention: cdk.Duration.days(7),
      // Production: protected from deletion and RETAINed if the stack is ever
      // destroyed. Staging: still takes a final snapshot, but can be removed.
      deletionProtection: isProduction,
      removalPolicy: isProduction ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.SNAPSHOT,
    });

    new cdk.CfnOutput(this, "DatabaseSecretArn", {
      value: this.dbInstance.secret!.secretArn,
      description: "Secrets Manager secret holding the DB credentials + connection info",
    });
  }
}
