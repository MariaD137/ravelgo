import * as apprunner from "aws-cdk-lib/aws-apprunner";
import * as budgets from "aws-cdk-lib/aws-budgets";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cwActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as logs from "aws-cdk-lib/aws-logs";
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
      alarmName: "ravelgo-backend-5xx-errors",
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
      alarmName: "ravelgo-db-high-cpu",
      alarmDescription: "RDS CPU above 80% for 15 minutes straight",
      metric: props.dbInstance.metricCPUUtilization({ period: cdk.Duration.minutes(5) }),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    }).addAlarmAction(new cwActions.SnsAction(alertTopic));

    new cloudwatch.Alarm(this, "RdsFreeStorageAlarm", {
      alarmName: "ravelgo-db-low-storage",
      alarmDescription: "RDS free storage below 2 GiB",
      metric: props.dbInstance.metricFreeStorageSpace({ period: cdk.Duration.minutes(15) }),
      threshold: 2 * 1024 * 1024 * 1024,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    }).addAlarmAction(new cwActions.SnsAction(alertTopic));

    // --- Security-event alarms (IN-04 follow-up) --------------------------
    //
    // The backend emits one stable line per security-relevant event —
    // `SECURITY_EVENT <TYPE> ...` — from src/lib/security-log.ts (auth
    // failures, authorization failures, rate-limit hits, payment failures).
    // App Runner ships application logs to this log group; we turn those
    // lines into CloudWatch metrics with metric filters, then alarm on a
    // *spike* of each. Thresholds are deliberately set well above ordinary
    // background noise (an expired token here and there, the odd 403) so the
    // channel only fires on something worth investigating, not on normal use.
    //
    // The log group is created by App Runner on first deploy, so it's
    // imported by name rather than created here (creating it would collide).
    const appLogGroup = logs.LogGroup.fromLogGroupName(
      this,
      "AppRunnerAppLogs",
      `/aws/apprunner/${serviceName}/${serviceId}/application`,
    );

    const securityNamespace = "RavelGo/Security";

    // [event type, alarm-worthy count in 5 minutes, why this threshold]
    const securitySignals: Array<{ id: string; type: string; metricName: string; threshold: number; purpose: string }> = [
      // Expired/invalid tokens happen normally; only a burst (credential
      // stuffing, a token-replay probe) should page anyone.
      { id: "AuthFailure", type: "AUTH_FAILURE", metricName: "AuthFailures", threshold: 50, purpose: "Spike in 401s — possible credential stuffing or token probing" },
      // A legitimate user almost never hits a 403; a run of them means
      // someone is walking IDs / trying to reach endpoints above their role.
      { id: "AuthzFailure", type: "AUTHZ_FAILURE", metricName: "AuthzFailures", threshold: 20, purpose: "Spike in 403s — possible privilege-escalation or IDOR probing" },
      // Any sustained rate-limiting means something is hammering an endpoint.
      { id: "RateLimit", type: "RATE_LIMIT_EXCEEDED", metricName: "RateLimitHits", threshold: 20, purpose: "Sustained rate-limiting — an endpoint is being hammered" },
      // A cluster of failed charges is the classic signature of card testing.
      { id: "PaymentFailure", type: "PAYMENT_FAILURE", metricName: "PaymentFailures", threshold: 10, purpose: "Spike in failed payments — possible card-testing abuse" },
    ];

    for (const signal of securitySignals) {
      new logs.MetricFilter(this, `${signal.id}MetricFilter`, {
        logGroup: appLogGroup,
        filterPattern: logs.FilterPattern.literal(`"SECURITY_EVENT ${signal.type}"`),
        metricNamespace: securityNamespace,
        metricName: signal.metricName,
        metricValue: "1",
        defaultValue: 0,
      });

      new cloudwatch.Alarm(this, `${signal.id}Alarm`, {
        alarmName: `ravelgo-security-${signal.type.toLowerCase()}`,
        alarmDescription: signal.purpose,
        metric: new cloudwatch.Metric({
          namespace: securityNamespace,
          metricName: signal.metricName,
          statistic: "Sum",
          period: cdk.Duration.minutes(5),
        }),
        threshold: signal.threshold,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      }).addAlarmAction(new cwActions.SnsAction(alertTopic));
    }

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
