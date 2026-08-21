import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as budgets from "aws-cdk-lib/aws-budgets";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cwActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as rds from "aws-cdk-lib/aws-rds";
import * as sns from "aws-cdk-lib/aws-sns";
import * as subscriptions from "aws-cdk-lib/aws-sns-subscriptions";
import * as cdk from "aws-cdk-lib";
import type { Construct } from "constructs";

export interface MonitoringStackProps extends cdk.StackProps {
  service: apprunner.CfnService;
  dbInstance: rds.DatabaseInstance;
  // Both have sensible-but-fake defaults in bin/infra.ts — CDK can't know
  // a real alert address or dollar threshold, so override both:
  //   cdk deploy --context alertEmail=you@example.com --context monthlyBudgetUsd=150
  alertEmail: string;
  monthlyBudgetUsd: number;
  envName: string;
}

// IN-04: nothing alerted on cost or error spikes before this — a runaway
// RDS instance or a broken deploy could run for days unnoticed. Scoped to
// the handful of signals that actually matter for a single-instance,
// single-environment MVP: App Runner error rate, RDS running out of either
// CPU or disk, and total AWS spend. Add more (P99 latency, connection pool
// exhaustion) once there's real production traffic to know what else is
// worth watching — alerting on everything from day one just trains
// everyone to ignore the channel.
export class MonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    const alertTopic = new sns.Topic(this, "AlertTopic", { displayName: "RavelGo alerts" });
    alertTopic.addSubscription(new subscriptions.EmailSubscription(props.alertEmail));

    const serviceName = props.service.serviceName!;
    const serviceId = props.service.attrServiceId;

    new cloudwatch.Alarm(this, "AppRunner5xxAlarm", {
      alarmName: `${props.envName}-ravelgo-backend-5xx-errors`,
      alarmDescription: "More than 10 5xx responses from the backend in 5 minutes",
      metric: new cloudwatch.Metric({
        namespace: "AWS/AppRunner",
        metricName: "5xxStatusResponses",
        dimensionsMap: { ServiceName: serviceName, ServiceId: serviceId },
        statistic: "Sum",
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(new cwActions.SnsAction(alertTopic));

    new cloudwatch.Alarm(this, "RdsCpuAlarm", {
      alarmName: `${props.envName}-ravelgo-db-high-cpu`,
      alarmDescription: "RDS CPU above 80% for 15 minutes straight",
      metric: props.dbInstance.metricCPUUtilization({ period: cdk.Duration.minutes(5) }),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    }).addAlarmAction(new cwActions.SnsAction(alertTopic));

    new cloudwatch.Alarm(this, "RdsFreeStorageAlarm", {
      alarmName: `${props.envName}-ravelgo-db-low-storage`,
      alarmDescription: "RDS free storage below 2 GiB",
      metric: props.dbInstance.metricFreeStorageSpace({ period: cdk.Duration.minutes(15) }),
      threshold: 2 * 1024 * 1024 * 1024,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    }).addAlarmAction(new cwActions.SnsAction(alertTopic));

    new budgets.CfnBudget(this, "MonthlyBudget", {
      budget: {
        budgetType: "COST",
        timeUnit: "MONTHLY",
        budgetLimit: { amount: props.monthlyBudgetUsd, unit: "USD" },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: "ACTUAL",
            comparisonOperator: "GREATER_THAN",
            threshold: 80,
            thresholdType: "PERCENTAGE",
          },
          subscribers: [{ subscriptionType: "EMAIL", address: props.alertEmail }],
        },
        {
          notification: {
            notificationType: "FORECASTED",
            comparisonOperator: "GREATER_THAN",
            threshold: 100,
            thresholdType: "PERCENTAGE",
          },
          subscribers: [{ subscriptionType: "EMAIL", address: props.alertEmail }],
        },
      ],
    });

    new cdk.CfnOutput(this, "AlertTopicArn", { value: alertTopic.topicArn });
  }
}
