#!/usr/bin/env bash
# Assume the admin role and export AWS_* env vars for Terraform + Ansible.
# Source this file, do not execute it: `source scripts/assume-role.sh`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill in ROLE_ARN." >&2
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${ROLE_ARN:?ROLE_ARN not set in .env}"
: "${SESSION_NAME:=AWSCLI-Session}"

credentials=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "$SESSION_NAME" \
  --query 'Credentials' \
  --output json)

AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r '.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r '.SecretAccessKey')
AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r '.SessionToken')
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

if [[ -n "${AWS_REGION:-}" ]]; then
  export AWS_REGION
  export AWS_DEFAULT_REGION="$AWS_REGION"
fi

echo "Assumed role $ROLE_ARN (session: $SESSION_NAME)"
