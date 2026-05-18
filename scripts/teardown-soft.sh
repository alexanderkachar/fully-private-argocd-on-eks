#!/usr/bin/env bash
# Backup Gitea, destroy the platform layer, then destroy infra while preserving
# the Gitea data EBS volume for the next spin-up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
PLATFORM_DIR="${REPO_ROOT}/terraform/platform/environments/dev"
STATE_DIR="${REPO_ROOT}/.state"
VOLUME_FILE="${STATE_DIR}/gitea-data-volume-id"
AUTO_APPROVE="${AUTO_APPROVE:-true}"

tf_destroy() {
  local dir="$1"; shift
  local args=(terraform -chdir="$dir" destroy)
  [[ "$AUTO_APPROVE" == "true" ]] && args+=(-auto-approve)
  args+=("$@")
  "${args[@]}"
}

mkdir -p "$STATE_DIR"

echo "Running on-demand Gitea backup..."
"${SCRIPT_DIR}/backup-gitea.sh"

echo "Saving Gitea data volume ID..."
volume_id="$(terraform -chdir="$INFRA_DIR" output -raw gitea_data_volume_id)"
printf '%s\n' "$volume_id" > "$VOLUME_FILE"
echo "Saved $volume_id to $VOLUME_FILE"

echo "Destroying platform layer..."
tf_destroy "$PLATFORM_DIR"

echo "Removing managed Gitea data volume from Terraform state so AWS keeps it..."
terraform -chdir="$INFRA_DIR" state rm 'module.gitea_server.aws_ebs_volume.data[0]' >/dev/null 2>&1 || true
terraform -chdir="$INFRA_DIR" state rm 'module.gitea_server.aws_ebs_volume.data' >/dev/null 2>&1 || true

echo "Destroying infra layer..."
tf_destroy "$INFRA_DIR"

echo "Soft teardown complete. Preserved Gitea data volume: $volume_id"
