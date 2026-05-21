#!/usr/bin/env bash

set -euo pipefail

# Terraform can reach AWS APIs from the operator shell, but the EKS API is
# private. Apply, plan, and destroy need a cluster path for Helm releases.
case "${1:-}" in
  apply | destroy | plan)
    ;;
  *)
    exec terraform "$@"
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
LOCAL_PORT="${EKS_LOCAL_PORT:-16443}"

infra_output() {
  terraform -chdir="${INFRA_DIR}" output -raw "$1"
}

close_eks_access() {
  if [[ -n "${EKS_TUNNEL_PID:-}" ]] && kill -0 "${EKS_TUNNEL_PID}" >/dev/null 2>&1; then
    kill -- "-${EKS_TUNNEL_PID}" >/dev/null 2>&1 || true
    wait "${EKS_TUNNEL_PID}" 2>/dev/null || true
  fi
  [[ -n "${EKS_TUNNEL_LOG:-}" ]] && rm -f "${EKS_TUNNEL_LOG}"
}

CLUSTER_ENDPOINT="$(infra_output cluster_endpoint)"
if curl -ks --connect-timeout 3 --max-time 5 \
  "${CLUSTER_ENDPOINT}/readyz" >/dev/null 2>&1; then
  exec terraform "$@"
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "ERROR: ${CLUSTER_ENDPOINT} is unreachable and session-manager-plugin is not installed." >&2
  exit 1
fi

CLUSTER_HOST="${CLUSTER_ENDPOINT#https://}"
CLUSTER_HOST="${CLUSTER_HOST%%/*}"
RUNNER_INSTANCE_ID="$(infra_output gitea_runner_instance_id)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(infra_output region)}}"
EKS_TUNNEL_LOG="$(mktemp)"

echo "Opening SSM port forward to the private EKS API on 127.0.0.1:${LOCAL_PORT}..."
setsid aws ssm start-session \
  --target "${RUNNER_INSTANCE_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${CLUSTER_HOST}\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "${REGION}" \
  >"${EKS_TUNNEL_LOG}" 2>&1 &
EKS_TUNNEL_PID=$!

trap close_eks_access EXIT

export TF_VAR_cluster_api_host="https://127.0.0.1:${LOCAL_PORT}"
export TF_VAR_cluster_api_tls_server_name="${CLUSTER_HOST}"

for _ in $(seq 1 30); do
  if curl -ks --connect-timeout 2 --max-time 5 \
    "${TF_VAR_cluster_api_host}/readyz" >/dev/null 2>&1; then
    terraform "$@"
    exit
  fi

  if ! kill -0 "${EKS_TUNNEL_PID}" >/dev/null 2>&1; then
    echo "ERROR: EKS SSM port forward stopped before it became ready." >&2
    cat "${EKS_TUNNEL_LOG}" >&2
    exit 1
  fi
  sleep 2
done

echo "ERROR: timed out opening EKS SSM port forward." >&2
cat "${EKS_TUNNEL_LOG}" >&2
exit 1
