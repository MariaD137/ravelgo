#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { ApiStack } from "../lib/api-stack";
import { AuthStack } from "../lib/auth-stack";
import { CiStack } from "../lib/ci-stack";
import { DataStack } from "../lib/data-stack";
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

const network = new NetworkStack(app, "RavelGo-Network", { env });
const auth = new AuthStack(app, "RavelGo-Auth", { env });
const storage = new StorageStack(app, "RavelGo-Storage", { env });
const data = new DataStack(app, "RavelGo-Data", { env, vpc: network.vpc });

const api = new ApiStack(app, "RavelGo-Api", {
  env,
  vpc: network.vpc,
  dbInstance: data.dbInstance,
  dbSecurityGroup: data.dbSecurityGroup,
  documentsBucket: storage.documentsBucket,
  assetsBucket: storage.assetsBucket,
  cognitoUserPoolId: auth.userPool.userPoolId,
  cognitoUserPoolClientId: auth.userPoolClient.userPoolClientId,
  allowedOrigins,
});

new CiStack(app, "RavelGo-CI", {
  env,
  repository: api.repository,
  service: api.service,
  githubOrg,
  githubRepo,
  githubBranch,
});
