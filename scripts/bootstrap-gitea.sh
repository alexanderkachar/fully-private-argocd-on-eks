#!/usr/bin/env bash
# bootstrap-gitea.sh — populate Gitea with the two repos ArgoCD consumes.
#
# Runs from operator laptop with VPN connected and AWS credentials active.
# Idempotent: org and repo creation are skipped when they already exist.
#
# Prerequisites: git, curl, jq, rsync, aws cli, terraform
# Usage: ./scripts/bootstrap-gitea.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"
DRY_RUN=false

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ---------- resolve outputs from Terraform ----------

tf_output() {
  local key="$1"
  local val
  if ! val=$(terraform -chdir="$INFRA_DIR" output -raw "$key" 2>/dev/null); then
    echo "ERROR: could not read '${key}' from Terraform infra output." >&2
    echo "       Run 'terraform -chdir=${INFRA_DIR} apply' first." >&2
    exit 1
  fi
  echo "$val"
}

GITEA_HOSTNAME=$(tf_output gitea_hostname)
ADMIN_USERNAME=$(tf_output gitea_admin_username)
TOKEN_SSM_NAME=$(tf_output gitea_admin_api_token_ssm_name)
ECR_REGISTRY=$(tf_output ecr_registry_url)
APP_ECR_IMAGE_URI=$(tf_output app_ecr_image_uri)
GRAFANA_TG_ARN=$(tf_output grafana_target_group_arn)
APP_TG_ARN=$(tf_output app_target_group_arn)

GITEA_URL="https://${GITEA_HOSTNAME}"
GITEA_ORG="fp-argo"
PLATFORM_MANIFESTS_URL="${GITEA_URL}/${GITEA_ORG}/platform-manifests.git"
EXPRESS_APP_URL="${GITEA_URL}/${GITEA_ORG}/express-app.git"

echo "Gitea URL              : ${GITEA_URL}"
echo "Admin user             : ${ADMIN_USERNAME}"
echo "Org                    : ${GITEA_ORG}"
echo "ECR registry           : ${ECR_REGISTRY}"
echo "App ECR image URI      : ${APP_ECR_IMAGE_URI}"
echo "Grafana target group   : ${GRAFANA_TG_ARN}"
echo "App target group       : ${APP_TG_ARN}"
echo ""

# ---------- read admin API token from SSM ----------

echo "Reading admin API token from SSM (${TOKEN_SSM_NAME})…"
ADMIN_TOKEN=$(aws ssm get-parameter \
  --name "${TOKEN_SSM_NAME}" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

if [[ -z "$ADMIN_TOKEN" ]]; then
  echo "ERROR: SSM parameter ${TOKEN_SSM_NAME} is empty — Gitea may not have finished booting." >&2
  echo "       Wait for user_data to complete, then retry." >&2
  exit 1
fi

# ---------- helpers ----------

gitea_api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-s -o /dev/null -w "%{http_code}"
    -X "$method"
    -H "Authorization: token ${ADMIN_TOKEN}"
    -H "Content-Type: application/json"
    "${GITEA_URL}/api/v1${path}"
  )
  [[ -n "$data" ]] && args+=(-d "$data")
  curl "${args[@]}"
}

gitea_api_json() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-s
    -X "$method"
    -H "Authorization: token ${ADMIN_TOKEN}"
    -H "Content-Type: application/json"
    "${GITEA_URL}/api/v1${path}"
  )
  [[ -n "$data" ]] && args+=(-d "$data")
  curl "${args[@]}"
}

# ---------- 1. create org ----------

echo "Creating org '${GITEA_ORG}'…"
status=$(gitea_api POST /orgs "{\"username\":\"${GITEA_ORG}\",\"visibility\":\"private\"}")
case "$status" in
  201) echo "  Created." ;;
  422) echo "  Already exists — skipping." ;;
  *)   echo "ERROR: unexpected status $status creating org." >&2; exit 1 ;;
esac

# ---------- 2. create repos ----------

create_repo() {
  local repo="$1"
  echo "Creating repo '${GITEA_ORG}/${repo}'…"
  status=$(gitea_api POST "/orgs/${GITEA_ORG}/repos" \
    "{\"name\":\"${repo}\",\"private\":true,\"auto_init\":true,\"default_branch\":\"main\"}")
  case "$status" in
    201) echo "  Created." ;;
    409) echo "  Already exists — skipping." ;;
    *)   echo "ERROR: unexpected status $status creating repo ${repo}." >&2; exit 1 ;;
  esac
}

create_repo "platform-manifests"
create_repo "express-app"
echo ""

# ---------- 3. build staged working trees with substitutions ----------
#
# The initial-manifests/ directory contains placeholder tokens that must be
# replaced with live values from Terraform outputs before pushing to Gitea.
# This function:
#   a) copies the source directory into a temp location,
#   b) runs sed substitutions on all text files in place,
#   c) optionally copies additional directories (charts, app source),
# then returns the temp dir path to the caller.

build_staged_tree() {
  local src_dir="$1"
  local staged
  staged=$(mktemp -d)

  rsync -a --exclude='.git' "${src_dir}/" "${staged}/"

  # Substitute all placeholders in one pass over every text file.
  # We use find + sed to avoid touching binary files (chart tarballs).
  while IFS= read -r -d '' f; do
    sed -i \
      -e "s|GITEA_PLATFORM_MANIFESTS_URL|${PLATFORM_MANIFESTS_URL}|g" \
      -e "s|GITEA_EXPRESS_APP_URL|${EXPRESS_APP_URL}|g" \
      -e "s|ECR_REGISTRY|${ECR_REGISTRY}|g" \
      -e "s|APP_ECR_IMAGE_URI|${APP_ECR_IMAGE_URI}|g" \
      -e "s|GITEA_GRAFANA_TARGET_GROUP_ARN|${GRAFANA_TG_ARN}|g" \
      -e "s|GITEA_APP_TARGET_GROUP_ARN|${APP_TG_ARN}|g" \
      "$f"
  done < <(find "$staged" -type f -not -path '*/.git/*' -not -name '*.tgz' -not -name '*.gz' -print0)

  echo "$staged"
}

# ---------- 4. push initial content ----------

push_content() {
  local repo="$1"
  local staged_dir="$2"

  echo "Pushing initial content to '${GITEA_ORG}/${repo}'…"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  (dry-run, skipping git push)"
    return
  fi

  local clone_dir
  clone_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf ${clone_dir}" RETURN

  git clone \
    "https://${ADMIN_USERNAME}:${ADMIN_TOKEN}@${GITEA_HOSTNAME}/${GITEA_ORG}/${repo}.git" \
    "${clone_dir}/${repo}"

  rsync -a --exclude='.git' "${staged_dir}/" "${clone_dir}/${repo}/"

  pushd "${clone_dir}/${repo}" > /dev/null

  git config user.email "bootstrap@fp-argo"
  git config user.name  "Bootstrap Script"

  git add -A

  if git diff --cached --quiet; then
    echo "  No changes to push — repo already has this content."
  else
    git commit -m "chore: bootstrap initial content"
    git push origin main
    echo "  Pushed."
  fi

  popd > /dev/null
  trap - RETURN
}

# ---------- platform-manifests ----------

echo "=== platform-manifests ==="
pm_staged=$(build_staged_tree "${REPO_ROOT}/initial-manifests/platform-manifests")
# Observability umbrella chart: copy from local charts/observability/ into the
# platform-manifests staged tree so ArgoCD can sync it without public Helm access.
mkdir -p "${pm_staged}/observability/chart"
rsync -a --exclude='.git' "${REPO_ROOT}/charts/observability/" "${pm_staged}/observability/chart/"
push_content "platform-manifests" "$pm_staged"
rm -rf "$pm_staged"
echo ""

# ---------- express-app ----------

echo "=== express-app ==="
ea_staged=$(build_staged_tree "${REPO_ROOT}/initial-manifests/express-app")
# App source code
rsync -a --exclude='.git' "${REPO_ROOT}/app/" "${ea_staged}/app/"
# Helm chart for the app
rsync -a --exclude='.git' "${REPO_ROOT}/charts/express-app/" "${ea_staged}/chart/"
push_content "express-app" "$ea_staged"
rm -rf "$ea_staged"
echo ""

# ---------- 5. create access tokens and store in SSM ----------
#
# Gitea 1.22 fine-grained PATs. Created via POST /users/{username}/tokens.
# ArgoCD and Image Updater authenticate as the admin user over HTTPS.
# Token values are returned only at creation time — if the token already exists
# the Gitea API returns 422 and the SSM write is skipped (existing value preserved).

create_access_token() {
  local token_name="$1"
  local ssm_name="$2"
  local scopes="$3"  # JSON array string, e.g. '["repository:read","repository:write"]'

  echo "Creating access token '${token_name}'…"

  local response
  response=$(gitea_api_json POST \
    "/users/${ADMIN_USERNAME}/tokens" \
    "{\"name\":\"${token_name}\",\"scopes\":${scopes}}")

  local token_val
  token_val=$(echo "$response" | jq -r '.sha1 // empty')

  if [[ -z "$token_val" ]]; then
    local msg
    msg=$(echo "$response" | jq -r '.message // "unknown error"')
    if echo "$msg" | grep -qi "already"; then
      echo "  Token '${token_name}' already exists — existing SSM value preserved."
      return
    fi
    echo "ERROR: could not create access token '${token_name}': ${msg}" >&2
    echo "       Full response: ${response}" >&2
    exit 1
  fi

  echo "  Token created. Writing to SSM (${ssm_name})…"

  if [[ "$DRY_RUN" == false ]]; then
    aws ssm put-parameter \
      --name "${ssm_name}" \
      --type "SecureString" \
      --value "${token_val}" \
      --overwrite \
      > /dev/null
    echo "  Stored."
  else
    echo "  (dry-run, skipping SSM write)"
  fi
}

# platform-manifests token: read + write (Image Updater writes back commits)
create_access_token \
  "argocd-image-updater" \
  "/fp-argo/gitea/platform-deploy-token" \
  '["repository:read","repository:write"]'

# express-app token: read-only (ArgoCD reads the Helm chart)
create_access_token \
  "argocd-express-app" \
  "/fp-argo/gitea/express-app-deploy-token" \
  '["repository:read"]'

echo ""
echo "Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/mirror-actions.sh to mirror GitHub actions into Gitea."
echo "  2. Run 'terraform -chdir=terraform/platform/environments/dev apply'."
