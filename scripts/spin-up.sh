#!/usr/bin/env bash
# Full cold-start sequence for the dev environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
PLATFORM_DIR="${REPO_ROOT}/terraform/platform/environments/dev"
STATE_DIR="${REPO_ROOT}/.state"
VOLUME_FILE="${STATE_DIR}/gitea-data-volume-id"
AUTO_APPROVE="${AUTO_APPROVE:-true}"

tf_apply() {
  local dir="$1"; shift
  local args=(terraform -chdir="$dir" apply)
  [[ "$AUTO_APPROVE" == "true" ]] && args+=(-auto-approve)
  args+=("$@")
  "${args[@]}"
}

infra_args=()
if [[ -s "$VOLUME_FILE" ]]; then
  volume_id="$(tr -d '[:space:]' < "$VOLUME_FILE")"
  if [[ -n "$volume_id" ]]; then
    echo "Reattaching preserved Gitea data volume: $volume_id"
    infra_args+=(-var "gitea_data_volume_id=$volume_id")
  fi
fi

echo "Applying infra layer..."
tf_apply "$INFRA_DIR" "${infra_args[@]}"

echo "Waiting for Gitea runner registration token in SSM..."
runner_token_name="$(terraform -chdir="$INFRA_DIR" output -raw gitea_runner_token_ssm_name)"
aws_region="$(terraform -chdir="$INFRA_DIR" output -raw region 2>/dev/null || true)"
aws_region="${aws_region:-${AWS_REGION:-us-east-1}}"
for _ in $(seq 1 90); do
  if aws ssm get-parameter --name "$runner_token_name" --with-decryption --region "$aws_region" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done
aws ssm get-parameter --name "$runner_token_name" --with-decryption --region "$aws_region" >/dev/null

echo "Mirroring platform images..."
"${SCRIPT_DIR}/mirror-images.sh"

echo "Bootstrapping Gitea repositories..."
"${SCRIPT_DIR}/bootstrap-gitea.sh"

echo "Mirroring Gitea Actions dependencies..."
"${SCRIPT_DIR}/mirror-actions.sh"

echo "Applying platform layer..."
tf_apply "$PLATFORM_DIR"

echo "Spin-up complete."
