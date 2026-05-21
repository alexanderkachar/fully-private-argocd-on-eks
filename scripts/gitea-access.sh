#!/usr/bin/env bash

# Exports GITEA_ACCESS_URL for scripts that need to reach private Gitea during
# cold start. If the canonical URL is unreachable, use an SSM port forward to
# the EC2 instance's local HTTP port.
open_gitea_access() {
  local canonical_url="$1"
  local instance_id="$2"
  local region="$3"
  local local_port="${GITEA_LOCAL_PORT:-13000}"

  GITEA_ACCESS_URL="$canonical_url"
  if curl -fsSk --connect-timeout 3 --max-time 5 \
    "${GITEA_ACCESS_URL}/api/healthz" >/dev/null 2>&1; then
    export GITEA_ACCESS_URL
    return
  fi

  if ! command -v session-manager-plugin >/dev/null 2>&1; then
    echo "ERROR: ${canonical_url} is unreachable and session-manager-plugin is not installed." >&2
    exit 1
  fi

  GITEA_TUNNEL_LOG=$(mktemp)
  echo "Opening SSM port forward to Gitea on 127.0.0.1:${local_port}..."
  setsid aws ssm start-session \
    --target "$instance_id" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"${local_port}\"]}" \
    --region "$region" \
    >"$GITEA_TUNNEL_LOG" 2>&1 &
  GITEA_TUNNEL_PID=$!
  GITEA_ACCESS_URL="http://127.0.0.1:${local_port}"
  export GITEA_ACCESS_URL

  trap close_gitea_access EXIT

  for _ in $(seq 1 30); do
    if curl -fsS --connect-timeout 2 --max-time 5 \
      "${GITEA_ACCESS_URL}/api/healthz" >/dev/null 2>&1; then
      return
    fi

    if ! kill -0 "$GITEA_TUNNEL_PID" >/dev/null 2>&1; then
      echo "ERROR: Gitea SSM port forward stopped before it became ready." >&2
      cat "$GITEA_TUNNEL_LOG" >&2
      exit 1
    fi
    sleep 2
  done

  echo "ERROR: timed out opening Gitea SSM port forward." >&2
  cat "$GITEA_TUNNEL_LOG" >&2
  exit 1
}

close_gitea_access() {
  if [[ -n "${GITEA_TUNNEL_PID:-}" ]] && kill -0 "$GITEA_TUNNEL_PID" >/dev/null 2>&1; then
    kill -- "-$GITEA_TUNNEL_PID" >/dev/null 2>&1 || true
    wait "$GITEA_TUNNEL_PID" 2>/dev/null || true
  fi
  [[ -n "${GITEA_TUNNEL_LOG:-}" ]] && rm -f "$GITEA_TUNNEL_LOG"
}
