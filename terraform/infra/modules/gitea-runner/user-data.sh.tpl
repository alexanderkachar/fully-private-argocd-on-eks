#!/bin/bash
# Rendered runner compose fingerprint: ${compose_sha}
# Rendered runner config fingerprint: ${config_sha}
set -eux
exec > /var/log/gitea-runner-bootstrap.log 2>&1

REGION="${region}"
CONFIG_BUCKET="${config_bucket}"
RUNNER_TOKEN_SSM="${runner_token_ssm_name}"
RUNNER_READY_SSM_PREFIX="${runner_ready_ssm_prefix}"
GITEA_URL="${gitea_instance_url}"
RUNNER_VERSION="${runner_version}"
RUNNER_NAME="${runner_name}"

retry() {
  local attempts="$1"
  local delay="$2"
  shift 2

  local attempt=1
  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi
    echo "Attempt $attempt/$attempts failed: $*. Retrying in $${delay}s." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

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
retry 18 10 aws s3 cp "s3://$CONFIG_BUCKET/runner/docker-compose.yml" /opt/runner/compose/docker-compose.yml --region "$REGION"
retry 18 10 aws s3 cp "s3://$CONFIG_BUCKET/runner/config.yaml" /opt/runner/config/config.yaml --region "$REGION"

# Poll SSM until the registration token exists (Gitea may still be coming up).
TOKEN=""
TOKEN_OUTPUT=""
for _ in $(seq 1 90); do
  if TOKEN_OUTPUT=$(aws ssm get-parameter --name "$RUNNER_TOKEN_SSM" --with-decryption --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
    TOKEN=$(printf '%s\n' "$TOKEN_OUTPUT" | grep -Eo '[[:alnum:]]{40}' | tail -n 1)
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
retry 60 5 curl -fsSk "$GITEA_URL/api/healthz" >/dev/null

# Register the runner once. After register, .runner inside /opt/runner/data
# holds the credentials and we just `docker compose up` on subsequent boots.
register_runner() {
  docker run --rm \
    --entrypoint act_runner \
    -v /opt/runner/data:/data \
    -v /opt/runner/config/config.yaml:/config/config.yaml:ro \
    "gitea/act_runner:$RUNNER_VERSION" \
    -c /config/config.yaml \
    register \
      --no-interactive \
      --instance "$GITEA_URL" \
      --token "$TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "ubuntu-latest:docker://catthehacker/ubuntu:act-24.04,self-hosted"
}

if [[ ! -f /opt/runner/data/.runner ]]; then
  retry 12 10 register_runner
fi

# Start the long-running daemon.
cd /opt/runner/compose
docker compose up -d

runner_is_running() {
  [[ "$(docker inspect --format='{{.State.Running}}' gitea-runner 2>/dev/null)" == "true" ]]
}

retry 12 5 runner_is_running

IMDS_TOKEN=$(curl -fsS -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
INSTANCE_ID=$(curl -fsS \
  -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
aws ssm put-parameter \
  --name "$RUNNER_READY_SSM_PREFIX/$INSTANCE_ID" \
  --type String \
  --value "$INSTANCE_ID" \
  --overwrite \
  --region "$REGION"
