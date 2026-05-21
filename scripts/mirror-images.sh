#!/usr/bin/env bash
# mirror-images.sh — pull every image in images.yaml, retag to ECR, push.
# Idempotent: pushing to an immutable tag that already exists is a no-op
# (ECR returns an error that this script swallows with a warning).
#
# Prerequisites: docker, aws cli, python3 with PyYAML
# Must run from operator laptop with VPN connected and AWS credentials active.
#
# Usage: ./scripts/mirror-images.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_YAML="${SCRIPT_DIR}/images.yaml"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DRY_RUN=false

PYTHON_BIN="${PYTHON_BIN:-python3}"
if [[ -x "${REPO_ROOT}/.venv/bin/python" ]]; then
  PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
fi

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ---------- resolve ECR registry URL from Terraform output ----------

INFRA_DIR="${SCRIPT_DIR}/../terraform/infra/environments/dev"

if ! ECR_REGISTRY=$(terraform -chdir="$INFRA_DIR" output -raw ecr_registry_url 2>/dev/null); then
  echo "ERROR: could not read ecr_registry_url from Terraform infra output." >&2
  echo "       Run 'terraform -chdir=$INFRA_DIR apply' first." >&2
  exit 1
fi
AWS_REGION=$(terraform -chdir="$INFRA_DIR" output -raw region 2>/dev/null || true)
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION=$(aws configure get region 2>/dev/null || true)
fi
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "ECR registry: ${ECR_REGISTRY}"

# ---------- authenticate Docker to ECR ----------

if [[ "$DRY_RUN" == false ]]; then
  echo "Authenticating Docker to ECR…"
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
fi

# ---------- mirror loop ----------

images_tsv=$("$PYTHON_BIN" - "$IMAGES_YAML" <<'PY'
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as images_file:
    images = yaml.safe_load(images_file).get("images", [])

if not isinstance(images, list):
    raise SystemExit("images.yaml must contain an images list")

for index, image in enumerate(images):
    try:
        source = str(image["source"])
        dest = str(image["dest"])
        tag = str(image["tag"])
    except (KeyError, TypeError) as exc:
        raise SystemExit(f"images[{index}] is missing source, dest, or tag") from exc
    print("\t".join((source, dest, tag)))
PY
)

image_rows=()
if [[ -n "$images_tsv" ]]; then
  mapfile -t image_rows <<< "$images_tsv"
fi

total="${#image_rows[@]}"
echo "Mirroring ${total} images…"
echo ""

success=0
skipped=0
failed=0

for image_row in "${image_rows[@]}"; do
  IFS=$'\t' read -r source dest tag <<< "$image_row"

  dest_uri="${ECR_REGISTRY}/${dest}:${tag}"

  echo "  [mirror] ${source}  →  ${dest_uri}"

  if [[ "$DRY_RUN" == true ]]; then
    echo "           (dry-run, skipping docker pull/push)"
    ((skipped += 1))
    continue
  fi

  if ! docker pull "${source}"; then
    echo "  WARNING: pull failed for ${source}, skipping." >&2
    ((failed += 1))
    continue
  fi

  docker tag "${source}" "${dest_uri}"

  # Push; swallow the immutable-tag-already-exists error so re-runs are safe.
  if push_output=$(docker push "${dest_uri}" 2>&1); then
    ((success += 1))
  else
    if echo "$push_output" | grep -q "image tag already exists\|ImageAlreadyExistsException\|tag immutability"; then
      echo "  SKIP: ${dest_uri} already in ECR (immutable tag)."
      ((skipped += 1))
    else
      echo "  ERROR: push failed for ${dest_uri}:" >&2
      echo "$push_output" >&2
      ((failed += 1))
    fi
  fi

  echo ""
done

echo "Done. success=${success} skipped=${skipped} failed=${failed}"

if (( failed > 0 )); then
  echo "WARNING: ${failed} image(s) failed to mirror. Re-run to retry." >&2
  exit 1
fi
