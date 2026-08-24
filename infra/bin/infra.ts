#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { ApiStack } from "../lib/api-stack";
import { AuthStack } from "../lib/auth-stack";
import { CiStack } from "../lib/ci-stack";
import { DataStack } from "../lib/data-stack";
import { MonitoringStack } from "../lib/monitoring-stack";
import { NetworkStack } from "../lib/network-stack";
import { StorageStack } from "../lib/storage-stack";

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION ?? "us-east-1",
};

const githubOrg = app.node.tryGetContext("githubOrg") ?? "MariaD137";
const githubRepo = app.node.tryGetContext("githubRepo") ?? "ravelgo";
const githubBranch = app.node.tryGetContext("githubBranch") ?? "main";
// Override with: cdk deploy --context allowedOrigins="https://admin.ravelgo.com,https://app.ravelgo.com"
const allowedOrigins = (app.node.tryGetContext("allowedOrigins") ?? "https://admin.ravelgo.com")
  .split(",")
  .map((origin: string) => origin.trim())
  .filter(Boolean);
const alertEmail = app.node.tryGetContext("alertEmail") ?? "alerts@ravelgo.example";
const monthlyBudgetUsd = Number(app.node.tryGetContext("monthlyBudgetUsd") ?? 100);

// IN-06: a second, independent environment in the same AWS account/region —
// `cdk deploy --all --context envName=staging`. Defaults to "production" so
// a plain `cdk deploy --all` behaves exactly as it always has (same stack
// IDs, same resource names) — this is additive, not a breaking rename.
const envName = app.node.tryGetContext("envName") ?? "production";
const suffix = envName === "production" ? "" : `-${envName}`;
const stackName = (base: string) => `${base}${suffix}`;

const network = new NetworkStack(app, stackName("RavelGo-Network"), { env });
const auth = new AuthStack(app, stackName("RavelGo-Auth"), { env, envName });
const storage = new StorageStack(app, stackName("RavelGo-Storage"), { env });
const data = new DataStack(app, stackName("RavelGo-Data"), { env, vpc: network.vpc });

const api = new ApiStack(app, stackName("RavelGo-Api"), {
  env,
  vpc: network.vpc,
  dbInstance: data.dbInstance,
  dbSecurityGroup: data.dbSecurityGroup,
  documentsBucket: storage.documentsBucket,
  assetsBucket: storage.assetsBucket,
  assetsCloudFrontDomain: storage.assetsDistribution.distributionDomainName,
  cognitoUserPoolId: auth.userPool.userPoolId,
  cognitoUserPoolClientId: auth.userPoolClient.userPoolClientId,
  allowedOrigins,
  envName,
});

new MonitoringStack(app, stackName("RavelGo-Monitoring"), {
  env,
  service: api.service,
  dbInstance: data.dbInstance,
  alertEmail,
  monthlyBudgetUsd,
});

// CI/CD (GitHub OIDC + deploy role) stays production-only: AWS only allows
// one OIDC provider per unique issuer URL per account, so a second CiStack
// for staging would fail at actual `cdk deploy` time (not something `cdk
// synth` alone would catch) unless it imported the existing provider
// instead of creating a new one. Safer to keep staging deploys manual
// (`cdk deploy --context envName=staging` from a developer machine with
// real AWS credentials) than to get account-wide OIDC sharing wrong.
if (envName === "production") {
  new CiStack(app, stackName("RavelGo-CI"), {
    env,
    repository: api.repository,
    service: api.service,
    githubOrg,
    githubRepo,
    githubBranch,
  });
}
