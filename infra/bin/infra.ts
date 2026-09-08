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

// First-deploy bootstrap only: `--context deployService=false` creates the
// ECR repo (so a first image can be pushed) without the App Runner service,
// which can't stabilize against an image that doesn't exist yet. Monitoring
// watches that service, so it's skipped on the same pass. Defaults to true,
// so `cdk deploy --all` and every redeploy behave exactly as before.
const deployService = app.node.tryGetContext("deployService") !== "false";

const network = new NetworkStack(app, stackName("RavelGo-Network"), { env, envName });
const auth = new AuthStack(app, stackName("RavelGo-Auth"), { env, envName });
const storage = new StorageStack(app, stackName("RavelGo-Storage"), { env });
const data = new DataStack(app, stackName("RavelGo-Data"), { env, vpc: network.vpc, envName });

// The three Flutter web apps are served from the assets CloudFront
// distribution, so browser calls from them carry that domain as their Origin
// and are subject to CORS (the mobile apps send no Origin and are unaffected).
// Always allow that domain in addition to any operator-supplied origins, so
// the deployed web apps can reach the API without a manual context override.
const assetsOrigin = `https://${storage.assetsDistribution.distributionDomainName}`;
const apiAllowedOrigins = Array.from(new Set([...allowedOrigins, assetsOrigin]));

const api = new ApiStack(app, stackName("RavelGo-Api"), {
  env,
  vpc: network.vpc,
  dbInstance: data.dbInstance,
  dbSecurityGroup: data.dbSecurityGroup,
  documentsBucket: storage.documentsBucket,
  assetsBucket: storage.assetsBucket,
  assetsCdnDomain: storage.assetsDistribution.distributionDomainName,
  cognitoUserPoolId: auth.userPool.userPoolId,
  cognitoUserPoolClientId: auth.userPoolClient.userPoolClientId,
  allowedOrigins: apiAllowedOrigins,
  envName,
  deployService,
  pinpointApplicationId: auth.pinpointApplicationId,
});

// Only meaningful once the App Runner service exists — its alarms and log
// metric filters reference the service directly. Skipped on a bootstrap pass.
const apiService = api.service;
if (deployService && apiService) {
  new MonitoringStack(app, stackName("RavelGo-Monitoring"), {
    env,
    service: apiService,
    dbInstance: data.dbInstance,
    alertEmail,
    monthlyBudgetUsd,
  });
}

// CI/CD (GitHub OIDC + deploy role), one CiStack per environment. AWS only
// allows one OIDC provider per unique issuer URL per account, so only the
// production instance below creates it — every other environment's CiStack
// imports that same provider by its account-scoped ARN (computed inside the
// stack itself; see ci-stack.ts) rather than creating a second one.
if (envName === "production" && apiService) {
  new CiStack(app, stackName("RavelGo-CI"), {
    env,
    repository: api.repository,
    service: apiService,
    githubOrg,
    githubRepo,
    githubBranch,
  });
}

// Staging's role additionally covers publishing the three Flutter web builds
// (production doesn't auto-deploy its web apps via CI yet, so its role stays
// narrower). Database migrations stay a deliberate manual step even for
// staging — see scripts/migrate-staging.sh and .github/workflows/staging-deploy.yml's
// "check-for-new-migrations" job, which reminds a human to run it rather than
// running it unattended.
if (envName === "staging" && apiService) {
  new CiStack(app, stackName("RavelGo-CI"), {
    env,
    repository: api.repository,
    service: apiService,
    githubOrg,
    githubRepo,
    githubBranch,
    environmentName: "staging",
    webAppsConfig: {
      assetsBucket: storage.assetsBucket,
      assetsDistribution: storage.assetsDistribution,
      configStackNames: [stackName("RavelGo-Storage"), stackName("RavelGo-Api"), stackName("RavelGo-Auth")],
    },
  });
}
