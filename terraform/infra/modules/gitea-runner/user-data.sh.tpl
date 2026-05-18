#!/bin/bash
set -eux
exec > /var/log/gitea-runner-bootstrap.log 2>&1

REGION="${region}"
CONFIG_BUCKET="${config_bucket}"
RUNNER_TOKEN_SSM="${runner_token_ssm_name}"
GITEA_URL="${gitea_instance_url}"
RUNNER_VERSION="${runner_version}"
RUNNER_NAME="${runner_name}"

dnf update -y
dnf install -y docker awscli jq

systemctl enable --now docker
usermod -aG docker ec2-user

# docker compose v2 plugin.
DOCKER_PLUGIN_DIR=/usr/libexec/docker/cli-plugins
mkdir -p "$DOCKER_PLUGIN_DIR"
curl -fsSL -o "$DOCKER_PLUGIN_DIR/docker-compose" \
  "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64"
chmod 0755 "$DOCKER_PLUGIN_DIR/docker-compose"

# Fetch rendered compose + runner config from S3.
mkdir -p /opt/runner/compose /opt/runner/config /opt/runner/data
aws s3 cp "s3://$CONFIG_BUCKET/runner/docker-compose.yml" /opt/runner/compose/docker-compose.yml --region "$REGION"
aws s3 cp "s3://$CONFIG_BUCKET/runner/config.yaml" /opt/runner/config/config.yaml --region "$REGION"

# Poll SSM until the registration token exists (Gitea may still be coming up).
TOKEN=""
for _ in $(seq 1 90); do
  if TOKEN=$(aws ssm get-parameter --name "$RUNNER_TOKEN_SSM" --with-decryption --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
    if [[ -n "$TOKEN" && "$TOKEN" != "None" ]]; then
      break
    fi
  fi
  sleep 10
done

if [[ -z "$TOKEN" || "$TOKEN" == "None" ]]; then
  echo "ERROR: runner registration token not available after waiting" >&2
  exit 1
fi

# Wait for Gitea to actually answer — registration fails otherwise.
for _ in $(seq 1 60); do
  if curl -fsSk "$GITEA_URL/api/v1/version" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

# Register the runner once. After register, .runner inside /opt/runner/data
# holds the credentials and we just `docker compose up` on subsequent boots.
if [[ ! -f /opt/runner/data/.runner ]]; then
  docker run --rm \
    -v /opt/runner/data:/data \
    -v /opt/runner/config/config.yaml:/config/config.yaml:ro \
    -e CONFIG_FILE=/config/config.yaml \
    "gitea/act_runner:$RUNNER_VERSION" \
    register \
      --no-interactive \
      --instance "$GITEA_URL" \
      --token "$TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "ubuntu-latest:docker://node:20-bookworm,self-hosted"
fi

# Start the long-running daemon.
cd /opt/runner/compose
docker compose up -d
