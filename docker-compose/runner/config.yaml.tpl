log:
  level: info

runner:
  file: /data/.runner
  capacity: 2
  envs: {}
  labels:
    - "ubuntu-latest:docker://node:20-bookworm"
    - "self-hosted"

cache:
  enabled: true
  dir: /data/cache

container:
  network: bridge
  privileged: false
  options: ""
  workdir_parent: /data/workspace

host:
  workdir_parent: /opt/runner/data/workspace
