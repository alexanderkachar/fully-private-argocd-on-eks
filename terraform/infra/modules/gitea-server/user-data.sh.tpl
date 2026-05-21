#!/bin/bash
set -eux
exec > /var/log/gitea-bootstrap.log 2>&1

REGION="${region}"
CONFIG_BUCKET="${config_bucket}"
BACKUP_BUCKET="${backup_bucket}"
GITEA_ADMIN_USER="${admin_username}"
ADMIN_PW_SSM="${admin_password_ssm_name}"
ADMIN_TOKEN_SSM="${admin_token_ssm_name}"
RUNNER_TOKEN_SSM="${runner_token_ssm_name}"

dnf update -y
dnf install -y docker awscli jq unzip sqlite cronie

# Docker
systemctl enable --now docker
systemctl enable --now crond
usermod -aG docker ec2-user

# docker compose v2 plugin (AL2023 ships docker but not the compose plugin).
DOCKER_PLUGIN_DIR=/usr/libexec/docker/cli-plugins
mkdir -p "$DOCKER_PLUGIN_DIR"
curl -fsSL -o "$DOCKER_PLUGIN_DIR/docker-compose" \
  "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64"
chmod 0755 "$DOCKER_PLUGIN_DIR/docker-compose"

# Mount the persistent data volume. Nitro instances expose EBS as NVMe;
# the udev symlink under /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<vol-id>
# is created by the AL2023 NVMe rules and is stable across reboots.
SHORT_VOL_ID="${data_volume_id_short}"
DATA_LINK="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol$${SHORT_VOL_ID}"

DATA_DEV=""
for _ in $(seq 1 60); do
  if [[ -e "$DATA_LINK" ]]; then
    DATA_DEV=$(readlink -f "$DATA_LINK")
    break
  fi
  sleep 2
done

if [[ -z "$DATA_DEV" || ! -e "$DATA_DEV" ]]; then
  echo "ERROR: could not resolve data volume device at $DATA_LINK" >&2
  exit 1
fi

if ! blkid "$DATA_DEV"; then
  mkfs -t ext4 -F "$DATA_DEV"
fi

mkdir -p /opt/gitea
if ! mountpoint -q /opt/gitea; then
  echo "$DATA_DEV /opt/gitea ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /opt/gitea
fi
mkdir -p /opt/gitea/data
chown -R 1000:1000 /opt/gitea/data

cat > /usr/local/bin/gitea-restore-latest.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
BACKUP_BUCKET="__BACKUP_BUCKET__"
REGION="__REGION__"
data="/opt/gitea/data"
workdir="/tmp/gitea-restore"
backup="/tmp/gitea-restore.zip"

latest_key=$(aws s3api list-objects-v2 \
  --bucket "$BACKUP_BUCKET" \
  --query 'reverse(sort_by(not_null(Contents, `[]`),&LastModified))[0].Key' \
  --output text \
  --region "$REGION")

if [[ -z "$latest_key" || "$latest_key" == "None" ]]; then
  echo "No Gitea backup found in s3://$BACKUP_BUCKET; starting fresh."
  exit 0
fi

echo "Restoring Gitea backup s3://$BACKUP_BUCKET/$latest_key"
rm -rf "$workdir"
mkdir -p "$workdir"
aws s3 cp "s3://$BACKUP_BUCKET/$latest_key" "$backup" --region "$REGION"
unzip -q "$backup" -d "$workdir"

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
rm -rf "$workdir" "$backup"
SCRIPT
sed -i "s|__BACKUP_BUCKET__|$BACKUP_BUCKET|g; s|__REGION__|$REGION|g" /usr/local/bin/gitea-restore-latest.sh
chmod 0755 /usr/local/bin/gitea-restore-latest.sh

if [[ ! -f /opt/gitea/data/gitea/gitea.db ]]; then
  /usr/local/bin/gitea-restore-latest.sh
fi

# Fetch the rendered docker-compose file.
mkdir -p /opt/gitea/compose
aws s3 cp "s3://$CONFIG_BUCKET/gitea/docker-compose.yml" /opt/gitea/compose/docker-compose.yml --region "$REGION"

# Start Gitea.
cd /opt/gitea/compose
docker compose up -d

# Wait for the API.
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:3000/api/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

# Generate (or fetch) admin password and create the admin user idempotently.
ADMIN_PW=$(aws ssm get-parameter --name "$ADMIN_PW_SSM" --with-decryption --region "$REGION" --query 'Parameter.Value' --output text)

if ! docker exec --user git gitea gitea --config /data/gitea/conf/app.ini admin user list 2>/dev/null | grep -q "^[[:space:]]*[0-9]\+[[:space:]]\+$GITEA_ADMIN_USER[[:space:]]"; then
  docker exec --user git gitea gitea --config /data/gitea/conf/app.ini admin user create \
    --username "$GITEA_ADMIN_USER" \
    --password "$ADMIN_PW" \
    --email "$GITEA_ADMIN_USER@example.invalid" \
    --admin \
    --must-change-password=false
fi

# Issue an API token if one isn't already stored. Token name is fixed so we
# can detect existence and avoid creating duplicates on every boot.
TOKEN_NAME="bootstrap"
if ! aws ssm get-parameter --name "$ADMIN_TOKEN_SSM" --region "$REGION" >/dev/null 2>&1; then
  TOKEN_OUT=$(docker exec --user git gitea gitea --config /data/gitea/conf/app.ini admin user generate-access-token \
    --username "$GITEA_ADMIN_USER" \
    --token-name "$TOKEN_NAME" \
    --scopes "all")
  TOKEN_VAL=$(echo "$TOKEN_OUT" | awk '/Access token was successfully created/ {print $NF}')
  if [[ -z "$TOKEN_VAL" ]]; then
    echo "ERROR: admin API token generation returned no token" >&2
    exit 1
  fi
  aws ssm put-parameter --name "$ADMIN_TOKEN_SSM" --type SecureString --value "$TOKEN_VAL" --overwrite --region "$REGION"
fi

# Generate a runner registration token. Gitea returns a fresh token each
# call; we only write to SSM if there isn't one yet, so the runner has a
# stable handshake value.
if ! aws ssm get-parameter --name "$RUNNER_TOKEN_SSM" --region "$REGION" >/dev/null 2>&1; then
  RUNNER_TOKEN=$(docker exec --user git gitea gitea --config /data/gitea/conf/app.ini actions generate-runner-token | tr -d '\r\n')
  if [[ -z "$RUNNER_TOKEN" ]]; then
    echo "ERROR: runner registration token generation returned no token" >&2
    exit 1
  fi
  aws ssm put-parameter --name "$RUNNER_TOKEN_SSM" --type SecureString --value "$RUNNER_TOKEN" --overwrite --region "$REGION"
fi

# Daily backup cron — runs `gitea dump` and uploads to the backups bucket.
cat > /etc/cron.d/gitea-backup <<CRON
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
AWS_DEFAULT_REGION=$REGION
0 2 * * * root /usr/local/bin/gitea-backup.sh
CRON

cat > /usr/local/bin/gitea-backup.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
BACKUP_BUCKET="__BACKUP_BUCKET__"
REGION="__REGION__"
ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
docker exec --user git gitea bash -lc "cd /tmp && gitea --config /data/gitea/conf/app.ini dump --type zip --file /tmp/dump-$ts.zip"
docker cp gitea:/tmp/dump-$ts.zip /tmp/dump-$ts.zip
docker exec gitea rm -f /tmp/dump-$ts.zip
aws s3 cp /tmp/dump-$ts.zip "s3://$BACKUP_BUCKET/daily/$ts.zip" --region "$REGION"
rm -f /tmp/dump-$ts.zip
SCRIPT
sed -i "s|__BACKUP_BUCKET__|$BACKUP_BUCKET|g; s|__REGION__|$REGION|g" /usr/local/bin/gitea-backup.sh
chmod 0755 /usr/local/bin/gitea-backup.sh
chmod 0644 /etc/cron.d/gitea-backup
