#!/usr/bin/env bash
#
# Grant a Cognito user a RavelGo role by adding them to a group.
#
# New sign-ups are auto-added to the "Rider" group by the PostConfirmation
# Lambda. Driver and Admin are elevated roles and are never granted
# automatically, so use this to promote a user for testing or onboarding.
#
# Usage:
#   bash scripts/set-role.sh <email> <Rider|Driver|Admin>
#
# Examples:
#   bash scripts/set-role.sh jane@example.com Driver
#   bash scripts/set-role.sh you@example.com Admin
#
set -euo pipefail

# Never let the AWS CLI open an interactive pager mid-script.
export AWS_PAGER=""

EMAIL="${1:-}"
ROLE="${2:-}"
ENVNAME="${ENVNAME:-staging}"

if [[ -z "$EMAIL" || -z "$ROLE" ]]; then
  echo "Usage: bash scripts/set-role.sh <email> <Rider|Driver|Admin>" >&2
  exit 1
fi

case "$ROLE" in
  Rider|Driver|Admin) ;;
  *)
    echo "Role must be one of: Rider, Driver, Admin (got '$ROLE')" >&2
    exit 1
    ;;
esac

POOL="$(aws cloudformation describe-stacks \
  --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
  --output text)"

if [[ -z "$POOL" || "$POOL" == "None" ]]; then
  echo "Could not find the user pool. Is the RavelGo-Auth-${ENVNAME} stack deployed?" >&2
  exit 1
fi

aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$POOL" \
  --username "$EMAIL" \
  --group-name "$ROLE"

echo "Added ${EMAIL} to the ${ROLE} group."
echo "They must sign out and sign in again for the new role to take effect."
