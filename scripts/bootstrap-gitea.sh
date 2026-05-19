#!/usr/bin/env bash
# bootstrap-gitea.sh — populate Gitea with the single express-app repo ArgoCD consumes.
#
# Per CLAUDE.md: Terraform owns the platform, Gitea owns only the app.
# There is no platform-manifests repo; ArgoCD watches exactly one Application.
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
AWS_REGION=$(tf_output region)
ECR_REGISTRY=$(tf_output ecr_registry_url)
APP_ECR_IMAGE_URI=$(tf_output app_ecr_image_uri)
APP_TG_ARN=$(tf_output app_target_group_arn)

GITEA_URL="https://${GITEA_HOSTNAME}"
GITEA_ORG="fp-argo"
EXPRESS_APP_URL="${GITEA_URL}/${GITEA_ORG}/express-app.git"

echo "Gitea URL              : ${GITEA_URL}"
echo "Admin user             : ${ADMIN_USERNAME}"
echo "Org                    : ${GITEA_ORG}"
echo "AWS region             : ${AWS_REGION}"
echo "ECR registry           : ${ECR_REGISTRY}"
echo "App ECR image URI      : ${APP_ECR_IMAGE_URI}"
echo "App target group       : ${APP_TG_ARN}"
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

# ---------- 2. create express-app repo ----------

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

create_repo "express-app"
echo ""

# ---------- 3. stage and push express-app content ----------
#
# The express-app repo contains:
#   app/                — Node source + Dockerfile (from REPO_ROOT/app)
#   chart/              — Helm chart (from REPO_ROOT/charts/express-app)
#   .gitea/workflows/   — build pipeline (from REPO_ROOT/initial-manifests/express-app)
# Placeholder tokens in any text file are replaced with live Terraform output values.

substitute_placeholders() {
  local staged="$1"
  while IFS= read -r -d '' f; do
    sed -i \
      -e "s|AWS_REGION|${AWS_REGION}|g" \
      -e "s|ECR_REGISTRY|${ECR_REGISTRY}|g" \
      -e "s|APP_ECR_IMAGE_URI|${APP_ECR_IMAGE_URI}|g" \
      -e "s|GITEA_APP_TARGET_GROUP_ARN|${APP_TG_ARN}|g" \
      -e "s|GITEA_EXPRESS_APP_URL|${EXPRESS_APP_URL}|g" \
      "$f"
  done < <(find "$staged" -type f -not -path '*/.git/*' -not -name '*.tgz' -not -name '*.gz' -print0)
}

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

echo "=== express-app ==="
ea_staged=$(mktemp -d)
rsync -a --exclude='.git' "${REPO_ROOT}/initial-manifests/express-app/" "${ea_staged}/"
rsync -a --exclude='.git' "${REPO_ROOT}/app/"                          "${ea_staged}/app/"
rsync -a --exclude='.git' "${REPO_ROOT}/charts/express-app/"           "${ea_staged}/chart/"
substitute_placeholders "$ea_staged"
push_content "express-app" "$ea_staged"
rm -rf "$ea_staged"
echo ""

# ---------- 4. create access tokens and store in SSM ----------
#
# Two tokens — distinct so we can rotate independently and follow least-privilege:
#   - argocd-express-app-deploy  (repository:read)  — used by ArgoCD to fetch the chart
#   - argocd-express-app-writer  (repository:read+write) — used by Image Updater to commit values-override.yaml
#
# Gitea 1.22 fine-grained PATs. POST /users/{username}/tokens returns sha1 only at creation.
# If the token already exists Gitea returns 422; we preserve any existing SSM value.

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
      --region "${AWS_REGION}" \
      > /dev/null
    echo "  Stored."
  else
    echo "  (dry-run, skipping SSM write)"
  fi
}

create_access_token \
  "argocd-express-app-deploy" \
  "/fp-argo/gitea/express-app-deploy-token" \
  '["repository:read"]'

create_access_token \
  "argocd-express-app-writer" \
  "/fp-argo/gitea/express-app-writer-token" \
  '["repository:read","repository:write"]'

echo ""
echo "Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/mirror-actions.sh to mirror GitHub actions into Gitea."
echo "  2. Run 'terraform -chdir=terraform/platform/environments/dev apply'."
