#!/usr/bin/env bash
# Restore the latest Gitea dump from S3 onto the current Gitea EC2 host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"

tf_output() {
  terraform -chdir="$INFRA_DIR" output -raw "$1"
}

INSTANCE_ID="$(tf_output gitea_server_instance_id)"
BACKUP_BUCKET="$(tf_output gitea_backup_bucket)"
REGION="${AWS_REGION:-}"
if [[ -z "$REGION" ]]; then
  REGION="$(tf_output region 2>/dev/null || true)"
fi
if [[ -z "$REGION" ]]; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
REGION="${REGION:-us-east-1}"

if [[ $# -gt 0 ]]; then
  BACKUP_KEY="$1"
else
  BACKUP_KEY="$(aws s3api list-objects-v2 \
    --bucket "$BACKUP_BUCKET" \
    --query 'reverse(sort_by(Contents,&LastModified))[0].Key' \
    --output text \
    --region "$REGION")"
fi

if [[ -z "$BACKUP_KEY" || "$BACKUP_KEY" == "None" ]]; then
  echo "No Gitea backups found in s3://${BACKUP_BUCKET}." >&2
  exit 1
fi

REMOTE_SCRIPT=$(cat <<'SCRIPT'
set -euo pipefail
backup="/tmp/gitea-restore.zip"
workdir="/tmp/gitea-restore"
data="/opt/gitea/data"

dnf install -y unzip sqlite >/dev/null 2>&1 || true
aws s3 cp "s3://__BACKUP_BUCKET__/__BACKUP_KEY__" "$backup" --region "__REGION__"
rm -rf "$workdir"
mkdir -p "$workdir"
unzip -q "$backup" -d "$workdir"

cd /opt/gitea/compose
docker compose down

mkdir -p "$data/gitea/conf" "$data/git/repositories"

if [[ -f "$workdir/gitea-app.ini" ]]; then
  cp "$workdir/gitea-app.ini" "$data/gitea/conf/app.ini"
fi

if [[ -f "$workdir/gitea-db.sql" ]]; then
  rm -f "$data/gitea/gitea.db"
  sqlite3 "$data/gitea/gitea.db" < "$workdir/gitea-db.sql"
fi

if [[ -f "$workdir/gitea-repo.zip" ]]; then
  rm -rf "$data/git/repositories"
  mkdir -p "$data/git/repositories"
  unzip -q "$workdir/gitea-repo.zip" -d "$data/git/repositories"
fi

if [[ -f "$workdir/gitea-lfs.zip" ]]; then
  rm -rf "$data/git/lfs"
  mkdir -p "$data/git/lfs"
  unzip -q "$workdir/gitea-lfs.zip" -d "$data/git/lfs"
fi

if [[ -f "$workdir/gitea-attachments.zip" ]]; then
  rm -rf "$data/gitea/attachments"
  mkdir -p "$data/gitea/attachments"
  unzip -q "$workdir/gitea-attachments.zip" -d "$data/gitea/attachments"
fi

chown -R 1000:1000 "$data"
docker compose up -d
rm -rf "$workdir" "$backup"
SCRIPT
)

REMOTE_SCRIPT="${REMOTE_SCRIPT//__BACKUP_BUCKET__/$BACKUP_BUCKET}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__BACKUP_KEY__/$BACKUP_KEY}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REGION__/$REGION}"
PARAMETERS="$(jq -n --arg commands "$REMOTE_SCRIPT" '{commands: ($commands | split("\n"))}')"

echo "Restoring s3://${BACKUP_BUCKET}/${BACKUP_KEY} on ${INSTANCE_ID}"
COMMAND_ID="$(aws ssm send-command \
  --document-name AWS-RunShellScript \
  --instance-ids "$INSTANCE_ID" \
  --parameters "$PARAMETERS" \
  --query 'Command.CommandId' \
  --output text \
  --region "$REGION")"

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json
