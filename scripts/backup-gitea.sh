#!/usr/bin/env bash
# Run an on-demand Gitea dump on the EC2 host via SSM and upload it to S3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/terraform/infra/environments/dev"

tf_output() {
  terraform -chdir="$INFRA_DIR" output -raw "$1"
}

INSTANCE_ID="$(tf_output gitea_server_instance_id)"
BACKUP_BUCKET="$(tf_output gitea_backup_bucket)"
REGION="$(terraform -chdir="$INFRA_DIR" output -raw region 2>/dev/null || true)"
if [[ -z "$REGION" ]]; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
REGION="${REGION:-us-east-1}"

REMOTE_SCRIPT=$(cat <<'SCRIPT'
set -euo pipefail
ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
dump="/tmp/gitea-manual-$ts.zip"
docker exec gitea bash -lc "cd /tmp && gitea --config /data/gitea/conf/app.ini dump --type zip --file $dump"
docker cp "gitea:$dump" "$dump"
docker exec gitea rm -f "$dump"
aws s3 cp "$dump" "s3://__BACKUP_BUCKET__/manual/$ts.zip" --region "__REGION__"
rm -f "$dump"
SCRIPT
)

REMOTE_SCRIPT="${REMOTE_SCRIPT//__BACKUP_BUCKET__/$BACKUP_BUCKET}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REGION__/$REGION}"
PARAMETERS="$(jq -n --arg commands "$REMOTE_SCRIPT" '{commands: ($commands | split("\n"))}')"

echo "Starting Gitea backup on ${INSTANCE_ID}; bucket=s3://${BACKUP_BUCKET}/manual/"
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
