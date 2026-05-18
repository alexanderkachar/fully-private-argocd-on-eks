# Runbook

This runbook assumes the dev environment under `terraform/*/environments/dev`, AWS credentials for the target account, and VPN/operator certificates already prepared.

## Prerequisites

- AWS CLI authenticated to the target account.
- Terraform, Helm, Docker, Git, Curl, JQ.
- Access to the configured S3 Terraform state bucket.
- ACM certificate for `*.alexanderkachar.com`.
- Public Route 53 zone for `alexanderkachar.com`, or manual DNS delegation documented before apply.
- Docker running locally for image mirroring.

## Spin Up

```bash
make spin-up
```

What it does:

- Applies the infra layer.
- Reattaches `.state/gitea-data-volume-id` if a soft teardown preserved one.
- Waits for the Gitea runner token in SSM.
- Mirrors third-party images from `scripts/images.yaml` into ECR.
- Bootstraps Gitea repos from `initial-manifests/`.
- Mirrors GitHub Actions dependencies into the local `actions` org in Gitea.
- Applies the platform layer.

Useful checks:

```bash
terraform -chdir=terraform/infra/environments/dev output
terraform -chdir=terraform/platform/environments/dev output
kubectl get pods -A
kubectl get applications -n argocd
kubectl get externalsecrets -A
```

Expected result:

- `https://gitea.alexanderkachar.com` reachable through VPN.
- `https://argocd.alexanderkachar.com` reachable through VPN.
- ArgoCD root app exists and starts syncing child apps.
- Express app may remain pending until the first Gitea Actions image build finishes.

## First App Deploy

Make a small application change, commit, and push to Gitea:

```bash
git clone https://gitea.alexanderkachar.com/fp-argo/express-app.git
cd express-app
printf '\n' >> app/public/index.html
git add app/public/index.html
git commit -m "feat: test private gitops deploy"
git push origin main
```

Watch:

```bash
aws ecr list-images --repository-name fp-argo-dev-app
kubectl logs -n argocd deploy/argocd-image-updater
kubectl get applications -n argocd
```

Expected flow:

- Gitea Actions builds and pushes an ECR image tagged with the commit SHA.
- Image Updater commits the new tag to `express-app/chart/values-override.yaml`.
- ArgoCD syncs the app.
- `https://app.alexanderkachar.com` serves the new version.

## Backup Gitea

```bash
make backup-gitea
```

This uses SSM Run Command to run `gitea dump` on the Gitea EC2 host and upload the archive to:

```text
s3://<gitea-backup-bucket>/manual/<timestamp>.zip
```

The Gitea EC2 host also installs a daily cron backup to `daily/`.

## Soft Teardown

```bash
make teardown-soft
```

What it does:

- Runs an on-demand Gitea backup.
- Saves the Gitea EBS data volume ID to `.state/gitea-data-volume-id`.
- Destroys the platform layer.
- Removes the Gitea EBS volume from Terraform state so AWS preserves it.
- Destroys the infra layer.

The next `make spin-up` reattaches the preserved volume automatically.

## Hard Teardown

```bash
CONFIRM_HARD_TEARDOWN=destroy-gitea-state make teardown-hard
```

This runs soft teardown and then deletes the preserved Gitea EBS volume.

Use this when you intentionally want to rebuild from S3 backup or discard Gitea state.

## Restore Gitea

Restore latest backup:

```bash
make restore
```

Restore a specific backup key:

```bash
./scripts/restore.sh manual/2026-05-18T10-00-00Z.zip
```

On a fresh data volume, Gitea user data also attempts a best-effort restore from the latest S3 backup before starting the container.

## VPN Cost Toggle

```bash
make vpn-down
make vpn-up
```

These toggle the Client VPN subnet association without touching the rest of infra. Keep VPN down when you are not actively operating the environment.

## Troubleshooting

Gitea UI unreachable:

- Confirm VPN is connected.
- Check private DNS resolution for `gitea.alexanderkachar.com`.
- Check internal ALB target health for the Gitea target group.
- Start an SSM session with `terraform output gitea_server_ssm_session_command`.
- Inspect `/var/log/gitea-bootstrap.log` and `docker ps`.

Runner offline:

- Confirm `/fp-argo/gitea/runner-registration-token` exists in SSM.
- Start an SSM session to the runner with `terraform output gitea_runner_ssm_session_command`.
- Check runner container logs and Gitea Actions admin page.

ArgoCD cannot read Gitea:

- Check `kubectl get externalsecrets -n argocd`.
- Confirm `/fp-argo/gitea/platform-deploy-token` and `/fp-argo/gitea/express-app-deploy-token` exist.
- Check ArgoCD repo server logs.
- Confirm internal Gitea hostname resolves inside the cluster.

Image pull failures:

- Confirm `scripts/images.yaml` includes the image and tag.
- Re-run `./scripts/mirror-images.sh`.
- Check ECR repository and tag existence.
- Confirm node role has ECR read access and ECR VPC endpoints are available.

Image Updater does not commit:

- Check `kubectl logs -n argocd deploy/argocd-image-updater`.
- Confirm the `express-app` Application annotations point at the app ECR repository.
- Confirm the write-back secret uses the express-app deploy token.
- Confirm the token has repository write scope in Gitea.

Terraform destroy fails on preserved Gitea volume:

- Soft teardown removes the managed volume from state before infra destroy. If interrupted, run:

```bash
terraform -chdir=terraform/infra/environments/dev state rm 'module.gitea_server.aws_ebs_volume.data[0]'
terraform -chdir=terraform/infra/environments/dev destroy
```

Keep the volume ID somewhere safe if you still want to preserve it.
