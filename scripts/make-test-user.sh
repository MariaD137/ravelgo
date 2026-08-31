#!/usr/bin/env bash
#
# Create a ready-to-use RavelGo test account in a chosen role.
#
# Unlike normal self-signup (which emails a 6-digit code), this creates the
# user directly with a known password and puts them straight into the right
# Cognito group, so you — or your client — can log into any of the three apps
# immediately and exercise the real role endpoints. Ideal for testing and demos.
#
# Usage:
#   bash scripts/make-test-user.sh <email> <Rider|Driver|Admin> [password]
#
# If no password is given, a strong one is generated and printed.
# Optional: set FIRST=Jane LAST=Doe to control the display name.
#
# Examples:
#   bash scripts/make-test-user.sh rider@example.com  Rider
#   bash scripts/make-test-user.sh driver@example.com Driver  'Driver#2026'
#   FIRST=Ada LAST=Lovelace bash scripts/make-test-user.sh admin@example.com Admin
#
set -euo pipefail

# Never let the AWS CLI open an interactive pager mid-script.
export AWS_PAGER=""

EMAIL="${1:-}"
ROLE="${2:-}"
PASSWORD="${3:-}"
ENVNAME="${ENVNAME:-staging}"
FIRST="${FIRST:-Test}"
LAST="${LAST:-User}"

if [[ -z "$EMAIL" || -z "$ROLE" ]]; then
  echo "Usage: bash scripts/make-test-user.sh <email> <Rider|Driver|Admin> [password]" >&2
  exit 1
fi

case "$ROLE" in
  Rider|Driver|Admin) ;;
  *)
    echo "Role must be one of: Rider, Driver, Admin (got '$ROLE')" >&2
    exit 1
    ;;
esac

# Cognito password policy: 8+ chars with upper, lower, and a digit.
if [[ -z "$PASSWORD" ]]; then
  PASSWORD="Ravel$(( RANDOM % 9000 + 1000 ))go!"
fi

POOL="$(aws cloudformation describe-stacks \
  --stack-name "RavelGo-Auth-${ENVNAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
  --output text)"

if [[ -z "$POOL" || "$POOL" == "None" ]]; then
  echo "Could not find the user pool. Is the RavelGo-Auth-${ENVNAME} stack deployed?" >&2
  exit 1
fi

# Create the user with a verified email so no confirmation code is needed.
# MessageAction=SUPPRESS stops Cognito from emailing a temporary password.
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL" \
  --username "$EMAIL" \
  --message-action SUPPRESS \
  --user-attributes \
      Name=email,Value="$EMAIL" \
      Name=email_verified,Value=true \
      Name=given_name,Value="$FIRST" \
      Name=family_name,Value="$LAST" \
  >/dev/null

# Set a permanent password so the account is immediately usable (no forced reset).
aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL" \
  --username "$EMAIL" \
  --password "$PASSWORD" \
  --permanent

# Put them in the requested role group.
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$POOL" \
  --username "$EMAIL" \
  --group-name "$ROLE"

echo ""
echo "===================================================="
echo " Test account ready — log in with these credentials:"
echo "   App:      ${ROLE}"
echo "   Email:    ${EMAIL}"
echo "   Password: ${PASSWORD}"
echo "===================================================="
