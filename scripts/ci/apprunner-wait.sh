#!/usr/bin/env bash
#
# Wait for an App Runner deployment to finish and fail if it did not succeed.
#
#   bash scripts/ci/apprunner-wait.sh <service-arn> <operation-id>
#
# `aws apprunner start-deployment` only QUEUES a rollout. A workflow that stops
# there shows green even when App Runner then fails or rolls the deployment
# back (bad image, crash on boot, failed health check) and the environment
# quietly keeps serving the previous build. Used by both
# .github/workflows/backend-deploy.yml and staging-deploy.yml.
#
# Prefers apprunner:ListOperations (reports SUCCEEDED / FAILED / ROLLBACK_*
# for the exact operation). If the deploy role was created before that
# permission was added to infra/lib/ci-stack.ts, falls back to polling
# apprunner:DescribeService (always granted) until the service leaves
# OPERATION_IN_PROGRESS — that cannot tell a rollback from a success on its
# own, which is why the caller must still run scripts/ci/backend-smoke.sh.
set -euo pipefail
export AWS_PAGER=""

SERVICE_ARN="${1:?usage: apprunner-wait.sh <service-arn> <operation-id>}"
OPERATION_ID="${2:?usage: apprunner-wait.sh <service-arn> <operation-id>}"
# 60 x 20s = 20 minutes; App Runner deploys usually take 3-6 minutes.
MAX_POLLS="${MAX_POLLS:-60}"
POLL_SECONDS="${POLL_SECONDS:-20}"

# Service ARNs look like arn:aws:apprunner:<region>:<account>:service/<name>/<id> —
# App Runner's own CloudWatch log groups are named /aws/apprunner/<name>/<id>/{service,application}.
APPRUNNER_SERVICE_NAME="$(cut -d/ -f2 <<<"$SERVICE_ARN")"
APPRUNNER_SERVICE_ID="$(cut -d/ -f3 <<<"$SERVICE_ARN")"

# Best-effort: print the deployment's own recent logs on a genuine failure so
# the actual crash/health-check reason (bad env var or secret, unhandled
# exception on boot, ...) shows up right in the workflow log instead of a
# bare status name. Needs logs:FilterLogEvents on the deploy role
# (infra/lib/ci-stack.ts's AppRunnerLogsReadOnly statement) — degrades to a
# one-line notice if that hasn't been granted yet (redeploy the CI stack).
dump_logs_on_failure() {
  for suffix in service application; do
    local group="/aws/apprunner/$APPRUNNER_SERVICE_NAME/$APPRUNNER_SERVICE_ID/$suffix"
    echo "--- last 15 minutes of $group ---"
    if ! aws logs tail "$group" --since 15m 2>/tmp/apprunner-logs.err; then
      if grep -q "AccessDenied" /tmp/apprunner-logs.err; then
        echo "(no logs:FilterLogEvents permission yet — redeploy the CI stack: infra/ npm run bootstrap-ci or bootstrap-ci-staging)"
      else
        cat /tmp/apprunner-logs.err
      fi
    fi
  done
}

use_operations=true
for ((i = 1; i <= MAX_POLLS; i++)); do
  if [[ "$use_operations" == true ]]; then
    if STATUS="$(aws apprunner list-operations --service-arn "$SERVICE_ARN" \
      --query "OperationSummaryList[?Id=='${OPERATION_ID}'].Status | [0]" --output text 2>/tmp/apprunner-wait.err)"; then
      echo "App Runner deployment status: $STATUS"
      case "$STATUS" in
        SUCCEEDED) exit 0 ;;
        FAILED|ROLLBACK_IN_PROGRESS|ROLLBACK_SUCCEEDED|ROLLBACK_FAILED)
          echo "::error::App Runner deployment ended in $STATUS — the service is still running the previous build."
          dump_logs_on_failure
          exit 1 ;;
      esac
    elif grep -q "AccessDenied" /tmp/apprunner-wait.err; then
      echo "::warning::The deploy role may not call apprunner:ListOperations yet — redeploy the CI stack (infra/: npm run bootstrap-ci or bootstrap-ci-staging) to enable exact rollout status. Falling back to the service status."
      use_operations=false
    else
      cat /tmp/apprunner-wait.err >&2
      exit 1
    fi
  fi
  if [[ "$use_operations" == false ]]; then
    SERVICE_STATUS="$(aws apprunner describe-service --service-arn "$SERVICE_ARN" --query Service.Status --output text)"
    echo "App Runner service status: $SERVICE_STATUS"
    case "$SERVICE_STATUS" in
      RUNNING) exit 0 ;;
      OPERATION_IN_PROGRESS) ;;
      *)
        echo "::error::App Runner service is $SERVICE_STATUS after the deployment."
        dump_logs_on_failure
        exit 1 ;;
    esac
  fi
  sleep "$POLL_SECONDS"
done
echo "::error::Timed out after $((MAX_POLLS * POLL_SECONDS / 60)) minutes waiting for the App Runner deployment."
exit 1
