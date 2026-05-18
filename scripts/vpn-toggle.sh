#!/usr/bin/env bash
# Toggle Client VPN subnet association cost while keeping the rest of infra unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
VOLUME_FILE="${REPO_ROOT}/.state/gitea-data-volume-id"
AUTO_APPROVE="${AUTO_APPROVE:-true}"

case "${1:-}" in
  up) vpn_associated=true ;;
  down) vpn_associated=false ;;
  *)
    echo "Usage: $0 up|down" >&2
    exit 2
    ;;
esac

args=(terraform -chdir="$INFRA_DIR" apply -var "vpn_associated=$vpn_associated")
[[ "$AUTO_APPROVE" == "true" ]] && args+=(-auto-approve)

if [[ -s "$VOLUME_FILE" ]]; then
  volume_id="$(tr -d '[:space:]' < "$VOLUME_FILE")"
  [[ -n "$volume_id" ]] && args+=(-var "gitea_data_volume_id=$volume_id")
fi

"${args[@]}"
