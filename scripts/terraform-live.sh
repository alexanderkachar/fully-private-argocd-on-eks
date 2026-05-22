#!/usr/bin/env bash
# Run a Terraform-compatible command while teeing its output to a log file that
# Ansible can relay during an async task.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <log-file> <terraform-command> <args...>" >&2
  exit 2
fi

log_file="$1"
shift

mkdir -p "$(dirname "$log_file")"
: > "$log_file"

exec > >(tee -a "$log_file") 2>&1
exec "$@"
