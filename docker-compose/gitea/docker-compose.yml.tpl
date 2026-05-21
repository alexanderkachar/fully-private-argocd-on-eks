services:
  gitea:
    image: gitea/gitea:${gitea_version}
    container_name: gitea
    restart: unless-stopped
    environment:
      USER_UID: "1000"
      USER_GID: "1000"
      GITEA__database__DB_TYPE: sqlite3
      GITEA__database__PATH: /data/gitea/gitea.db
      GITEA__security__INSTALL_LOCK: "true"
      GITEA__server__DOMAIN: ${gitea_domain}
      GITEA__server__ROOT_URL: https://${gitea_domain}/
      GITEA__server__HTTP_PORT: "3000"
      GITEA__server__SSH_DOMAIN: ${gitea_domain}
      GITEA__server__START_SSH_SERVER: "false"
      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__service__REQUIRE_SIGNIN_VIEW: "true"
      GITEA__actions__ENABLED: "true"
      GITEA__actions__DEFAULT_ACTIONS_URL: https://${gitea_domain}/actions
      GITEA__log__LEVEL: Info
    volumes:
      - /opt/gitea/data:/data
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:3000/api/healthz"]
      interval: 10s
      timeout: 5s
      retries: 30
