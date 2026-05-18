services:
  runner:
    image: gitea/act_runner:${runner_version}
    container_name: gitea-runner
    restart: unless-stopped
    environment:
      CONFIG_FILE: /config/config.yaml
      GITEA_INSTANCE_URL: ${gitea_instance_url}
      # Token is provided at first-boot by user_data via `act_runner register`;
      # after that, .runner state is persisted to /data and re-registration is
      # skipped on subsequent restarts.
    volumes:
      - /opt/runner/data:/data
      - /opt/runner/config:/config:ro
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on: []
