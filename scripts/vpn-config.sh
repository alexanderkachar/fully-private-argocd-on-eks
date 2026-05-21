#!/usr/bin/env bash
# vpn-config.sh — assemble the AWS Client VPN .ovpn file for this environment.
#
# Downloads the base config from AWS, embeds the client certificate and private
# key from Terraform state, and writes the result to ~/fp-argo-vpn.ovpn.
#
# Prerequisites: aws cli, terraform
# Usage: ./scripts/vpn-config.sh [--out <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../terraform/infra/environments/dev"
OUT="${HOME}/fp-argo-vpn.ovpn"

for arg in "$@"; do
  if [[ "$arg" == --out ]]; then
    shift; OUT="$1"; shift
  fi
done

# ---------- resolve outputs from Terraform ----------

tf_output() {
  local key="$1"
  local val
  if ! val=$(terraform -chdir="$INFRA_DIR" output -raw "$key" 2>/dev/null); then
    echo "ERROR: could not read '${key}' from Terraform infra output." >&2
    echo "       Run 'make spin-up' or 'source scripts/assume-role.sh && make vpn-up' first." >&2
    exit 1
  fi
  echo "$val"
}

ENDPOINT_ID=$(tf_output vpn_endpoint_id)
CLIENT_CERT=$(tf_output vpn_client_cert_pem)
CLIENT_KEY=$(tf_output vpn_client_private_key_pem)

# ---------- fetch base config from AWS ----------

echo "Fetching base config for endpoint ${ENDPOINT_ID}..."
BASE_CONFIG=$(aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id "$ENDPOINT_ID" \
  --region "$(tf_output region)" \
  --output text)

# ---------- assemble .ovpn ----------

{
  echo "$BASE_CONFIG"
  echo "<cert>"
  echo "$CLIENT_CERT"
  echo "</cert>"
  echo "<key>"
  echo "$CLIENT_KEY"
  echo "</key>"
} > "$OUT"

chmod 600 "$OUT"
echo "Written to ${OUT}"
