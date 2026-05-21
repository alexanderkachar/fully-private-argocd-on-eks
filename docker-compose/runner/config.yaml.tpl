log:
  level: info

runner:
  file: /data/.runner
  capacity: 2
  envs: {}
  labels:
    - "ubuntu-latest:docker://catthehacker/ubuntu:act-24.04"
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
