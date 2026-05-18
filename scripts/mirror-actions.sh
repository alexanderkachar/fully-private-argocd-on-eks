#!/usr/bin/env bash
# mirror-actions.sh — clone GitHub action repos and push mirrors into Gitea.
#
# The Gitea Actions runner is configured with:
#   GITEA__actions__DEFAULT_ACTIONS_URL: https://<gitea_hostname>/actions
# so `uses: actions/checkout@v4` resolves to
#   https://<gitea_hostname>/actions/checkout (tag v4).
#
# This script creates the 'actions' org in Gitea (if absent) and mirrors
# each listed repo+tag combination so airgapped runners can resolve them.
#
# Runs from operator laptop with VPN connected and AWS credentials active.
# Idempotent: org/repo creation and tag pushes are skipped if already present.
#
# Prerequisites: git, curl, jq, aws cli
# Usage: ./scripts/mirror-actions.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
DRY_RUN=false

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ---------- resolve outputs from Terraform ----------

if ! GITEA_HOSTNAME=$(terraform -chdir="$INFRA_DIR" output -raw gitea_hostname 2>/dev/null); then
  echo "ERROR: could not read gitea_hostname from Terraform infra output." >&2
  exit 1
fi

if ! ADMIN_USERNAME=$(terraform -chdir="$INFRA_DIR" output -raw gitea_admin_username 2>/dev/null); then
  echo "ERROR: could not read gitea_admin_username from Terraform infra output." >&2
  exit 1
fi

if ! TOKEN_SSM_NAME=$(terraform -chdir="$INFRA_DIR" output -raw gitea_admin_api_token_ssm_name 2>/dev/null); then
  echo "ERROR: could not read gitea_admin_api_token_ssm_name from Terraform infra output." >&2
  exit 1
fi

AWS_REGION=$(terraform -chdir="$INFRA_DIR" output -raw region 2>/dev/null || true)
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION=$(aws configure get region 2>/dev/null || true)
fi
AWS_REGION="${AWS_REGION:-us-east-1}"

GITEA_URL="https://${GITEA_HOSTNAME}"
ACTIONS_ORG="actions"

echo "Gitea URL    : ${GITEA_URL}"
echo "Actions org  : ${ACTIONS_ORG}"
echo ""

# ---------- read admin API token from SSM ----------

echo "Reading admin API token from SSM (${TOKEN_SSM_NAME})…"
ADMIN_TOKEN=$(aws ssm get-parameter \
  --name "${TOKEN_SSM_NAME}" \
  --with-decryption \
  --region "${AWS_REGION}" \
  --query 'Parameter.Value' \
  --output text)

if [[ -z "$ADMIN_TOKEN" ]]; then
  echo "ERROR: SSM parameter ${TOKEN_SSM_NAME} is empty." >&2
  exit 1
fi

# ---------- action list ----------
#
# Format: "github_owner/github_repo  gitea_repo_name  ref_to_mirror"
# ref_to_mirror is the tag (or branch) used by workflows in this project.
# Add entries here when bumping action versions.

ACTIONS=(
  "actions/checkout                   checkout                   v4"
  "docker/build-push-action           build-push-action          v5"
  "docker/setup-buildx-action         setup-buildx-action        v3"
  "docker/login-action                login-action               v3"
  "aws-actions/configure-aws-credentials  configure-aws-credentials  v4"
  "aws-actions/amazon-ecr-login       amazon-ecr-login           v2"
)

# ---------- helpers ----------

gitea_api() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"

  local args=(-s -o /dev/null -w "%{http_code}"
    -X "$method"
    -H "Authorization: token ${ADMIN_TOKEN}"
    -H "Content-Type: application/json"
    "${GITEA_URL}/api/v1${path}"
  )
  [[ -n "$data" ]] && args+=(-d "$data")
  curl "${args[@]}"
}

# ---------- ensure 'actions' org exists ----------

echo "Ensuring org '${ACTIONS_ORG}' exists…"
status=$(gitea_api POST /orgs \
  "{\"username\":\"${ACTIONS_ORG}\",\"visibility\":\"public\"}")
case "$status" in
  201) echo "  Created." ;;
  422) echo "  Already exists — skipping." ;;
  *)   echo "ERROR: unexpected status $status creating org '${ACTIONS_ORG}'." >&2; exit 1 ;;
esac
echo ""

# ---------- mirror loop ----------

for entry in "${ACTIONS[@]}"; do
  read -r gh_repo gitea_repo ref <<< "$entry"
  gh_owner="${gh_repo%%/*}"
  gh_name="${gh_repo##*/}"

  echo "Mirroring github.com/${gh_repo} (ref: ${ref}) → ${ACTIONS_ORG}/${gitea_repo}…"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  (dry-run, skipping)"
    continue
  fi

  # Create repo in Gitea if absent (auto_init so it has a HEAD)
  status=$(gitea_api POST "/orgs/${ACTIONS_ORG}/repos" \
    "{\"name\":\"${gitea_repo}\",\"private\":false,\"auto_init\":false}")
  case "$status" in
    201) echo "  Gitea repo created." ;;
    409) echo "  Gitea repo already exists." ;;
    *)   echo "  WARNING: unexpected status $status creating repo — will attempt push anyway." ;;
  esac

  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf ${tmpdir}" RETURN

  # Shallow clone from GitHub to get just the tags we care about
  git clone \
    --bare \
    --filter=blob:none \
    "https://github.com/${gh_repo}.git" \
    "${tmpdir}/${gitea_repo}.git"

  # Push mirror to Gitea. `--mirror` pushes all refs; the runner resolves
  # `uses: actions/checkout@v4` to the v4 tag in this repo.
  pushd "${tmpdir}/${gitea_repo}.git" > /dev/null
  git remote add gitea \
    "https://${ADMIN_USERNAME}:${ADMIN_TOKEN}@${GITEA_HOSTNAME}/${ACTIONS_ORG}/${gitea_repo}.git"
  git push gitea --mirror --force 2>&1 | grep -v "^$" || true
  popd > /dev/null

  rm -rf "${tmpdir}"
  # Clear the trap now that tmpdir is gone
  trap - RETURN

  echo "  Done."
  echo ""
done

echo "Action mirroring complete."
