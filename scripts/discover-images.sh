#!/usr/bin/env bash
# discover-images.sh — render Helm charts and emit a draft images.yaml snippet.
# Run once after bumping chart versions, then review and merge the output into
# scripts/images.yaml manually.
#
# Prerequisites: helm, sed, awk
# Run from the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

charts=(
  "${REPO_ROOT}/charts/observability"
)

# Remote charts to template (name, repo, version, extra-args)
declare -A remote_charts
remote_charts["argocd"]="argo-cd|https://argoproj.github.io/argo-helm|7.8.23|--set server.extraArgs[0]=--insecure"
remote_charts["argocd-image-updater"]="argocd-image-updater|https://argoproj.github.io/argo-helm|0.12.1|"
remote_charts["aws-load-balancer-controller"]="aws-load-balancer-controller|https://aws.github.io/eks-charts|1.13.0|--set clusterName=discover"
remote_charts["external-secrets"]="external-secrets|https://charts.external-secrets.io|0.14.0|"

all_images=()

# ---------- local charts ----------

for chart_dir in "${charts[@]}"; do
  chart_name=$(basename "$chart_dir")
  echo "# Templating local chart: ${chart_name}" >&2
  while IFS= read -r img; do
    all_images+=("$img")
  done < <(
    helm template discover "$chart_dir" 2>/dev/null \
      | grep -E '^\s+image:' \
      | sed 's/.*image: //;s/"//g;s/'"'"'//g' \
      | sort -u
  )
done

# ---------- remote charts ----------

for release in "${!remote_charts[@]}"; do
  IFS='|' read -r chart repo version extra_args <<< "${remote_charts[$release]}"
  echo "# Templating remote chart: ${chart} @ ${version}" >&2
  # shellcheck disable=SC2086
  while IFS= read -r img; do
    all_images+=("$img")
  done < <(
    helm template "$release" "$chart" \
      --repo "$repo" \
      --version "$version" \
      $extra_args \
      2>/dev/null \
      | grep -E '^\s+image:' \
      | sed 's/.*image: //;s/"//g;s/'"'"'//g' \
      | sort -u
  )
done

# ---------- emit draft YAML ----------

echo ""
echo "# --- draft images.yaml entries (review and merge into scripts/images.yaml) ---"
echo "images:"

declare -A seen
for img in "${all_images[@]}"; do
  [[ -z "$img" ]] && continue
  [[ -n "${seen[$img]+x}" ]] && continue
  seen[$img]=1

  # parse registry/repo:tag
  if [[ "$img" == *":"* ]]; then
    tag="${img##*:}"
    repo_path="${img%:*}"
  else
    tag="latest"
    repo_path="$img"
  fi

  # derive a short dest name from the last path component
  dest=$(basename "$repo_path")

  printf "  - source: %s\n" "$img"
  printf "    dest: %s\n"   "$dest"
  printf "    tag: %s\n"    "$tag"
done
