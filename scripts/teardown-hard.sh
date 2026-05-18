#!/usr/bin/env bash
# Full teardown, including any preserved Gitea data volume from soft teardown.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${REPO_ROOT}/.state"
VOLUME_FILE="${STATE_DIR}/gitea-data-volume-id"
AUTO_APPROVE="${AUTO_APPROVE:-true}"
REGION="${AWS_REGION:-}"
if [[ -z "$REGION" ]]; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
REGION="${REGION:-us-east-1}"

if [[ "${CONFIRM_HARD_TEARDOWN:-}" != "destroy-gitea-state" ]]; then
  echo "Hard teardown deletes the preserved Gitea EBS volume."
  echo "Re-run with CONFIRM_HARD_TEARDOWN=destroy-gitea-state to continue."
  exit 1
fi

"${SCRIPT_DIR}/teardown-soft.sh"

if [[ -s "$VOLUME_FILE" ]]; then
  volume_id="$(tr -d '[:space:]' < "$VOLUME_FILE")"
  echo "Deleting preserved Gitea data volume: $volume_id"
  aws ec2 wait volume-available --volume-ids "$volume_id" --region "$REGION" || true
  aws ec2 delete-volume --volume-id "$volume_id" --region "$REGION"
  rm -f "$VOLUME_FILE"
else
  echo "No preserved Gitea data volume file found."
fi

echo "Hard teardown complete."
