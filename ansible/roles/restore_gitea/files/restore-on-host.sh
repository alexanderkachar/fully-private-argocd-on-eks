#!/usr/bin/env bash
# Executed inside the Gitea EC2 host via SSM send-command.
# Templated env vars: BACKUP_BUCKET, BACKUP_KEY, AWS_REGION
set -euo pipefail

backup="/tmp/gitea-restore.zip"
workdir="/tmp/gitea-restore"
data="/opt/gitea/data"

dnf install -y unzip sqlite >/dev/null 2>&1 || true
aws s3 cp "s3://${BACKUP_BUCKET}/${BACKUP_KEY}" "$backup" --region "${AWS_REGION}"
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
