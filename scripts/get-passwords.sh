#!/usr/bin/env bash
# get-passwords.sh — print login credentials for Gitea, ArgoCD, and Grafana.
#
# Gitea password comes from SSM (no cluster access needed).
# ArgoCD and Grafana passwords live in Kubernetes secrets, so the script opens
# an SSM port forward to the private EKS API, runs kubectl, then tears it down.
#
# Prerequisites: aws cli, kubectl, terraform, session-manager-plugin
# Usage: ./scripts/get-passwords.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../terraform/infra/environments/dev"
LOCAL_PORT="${EKS_LOCAL_PORT:-16443}"
EKS_TUNNEL_LOG=""
EKS_TUNNEL_PID=""
KUBECONFIG=""

# ---------- helpers ----------

infra_output() {
  terraform -chdir="${INFRA_DIR}" output -raw "$1"
}

close_eks_tunnel() {
  if [[ -n "${EKS_TUNNEL_PID}" ]] && kill -0 "${EKS_TUNNEL_PID}" >/dev/null 2>&1; then
    kill -- "-${EKS_TUNNEL_PID}" >/dev/null 2>&1 || true
    wait "${EKS_TUNNEL_PID}" 2>/dev/null || true
  fi
  [[ -n "${EKS_TUNNEL_LOG}" ]] && rm -f "${EKS_TUNNEL_LOG}"
  [[ -n "${KUBECONFIG}" ]] && rm -f "${KUBECONFIG}"
}

trap close_eks_tunnel EXIT

# ---------- Gitea (SSM parameter — no cluster needed) ----------

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(infra_output region)}}"
GITEA_HOSTNAME="$(infra_output gitea_hostname)"
GITEA_USER="$(infra_output gitea_admin_username)"
GITEA_PASS="$(aws ssm get-parameter \
  --name "$(infra_output gitea_admin_password_ssm_name)" \
  --region "${REGION}" \
  --with-decryption \
  --query Parameter.Value \
  --output text)"

# ---------- open SSM tunnel to private EKS API ----------

CLUSTER_ENDPOINT="$(infra_output cluster_endpoint)"
CLUSTER_HOST="${CLUSTER_ENDPOINT#https://}"
CLUSTER_HOST="${CLUSTER_HOST%%/*}"
RUNNER_INSTANCE_ID="$(infra_output gitea_runner_instance_id)"

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "ERROR: session-manager-plugin is not installed." >&2
  exit 1
fi

EKS_TUNNEL_LOG="$(mktemp)"
echo "Opening SSM port forward to the private EKS API..." >&2
setsid aws ssm start-session \
  --target "${RUNNER_INSTANCE_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${CLUSTER_HOST}\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "${REGION}" \
  >"${EKS_TUNNEL_LOG}" 2>&1 &
EKS_TUNNEL_PID=$!

for _ in $(seq 1 30); do
  if curl -ks --connect-timeout 2 --max-time 5 \
    "https://127.0.0.1:${LOCAL_PORT}/readyz" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${EKS_TUNNEL_PID}" >/dev/null 2>&1; then
    echo "ERROR: EKS SSM port forward stopped before it became ready." >&2
    cat "${EKS_TUNNEL_LOG}" >&2
    exit 1
  fi
  sleep 2
done

KUBECONFIG="$(mktemp)"
aws eks update-kubeconfig \
  --name "$(infra_output cluster_name)" \
  --region "${REGION}" \
  --kubeconfig "${KUBECONFIG}" >/dev/null
KUBE="kubectl --kubeconfig ${KUBECONFIG} --server https://127.0.0.1:${LOCAL_PORT} --tls-server-name ${CLUSTER_HOST}"

# ---------- ArgoCD ----------

ARGOCD_HOSTNAME="$(infra_output argocd_hostname)"
ARGOCD_PASS="$($KUBE get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d)"

# ---------- Grafana ----------

GRAFANA_HOSTNAME="$(infra_output grafana_hostname)"
GRAFANA_USER="$($KUBE get secret observability-grafana \
  -n observability \
  -o jsonpath='{.data.admin-user}' | base64 -d)"
GRAFANA_PASS="$($KUBE get secret observability-grafana \
  -n observability \
  -o jsonpath='{.data.admin-password}' | base64 -d)"

# ---------- print ----------

echo ""
echo "Gitea    https://${GITEA_HOSTNAME}"
echo "  user:  ${GITEA_USER}"
echo "  pass:  ${GITEA_PASS}"
echo ""
echo "ArgoCD   https://${ARGOCD_HOSTNAME}"
echo "  user:  admin"
echo "  pass:  ${ARGOCD_PASS}"
echo ""
echo "Grafana  https://${GRAFANA_HOSTNAME}"
echo "  user:  ${GRAFANA_USER}"
echo "  pass:  ${GRAFANA_PASS}"
echo ""
