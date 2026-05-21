# Fully Private ArgoCD on EKS

A portfolio-scale Amazon EKS platform where the cluster has no public internet egress, GitOps runs through ArgoCD, CI/CD lives inside the VPC on self-hosted Gitea, and operator access is gated through AWS Client VPN. The Express demo app is the only public workload, exposed through a separate internet-facing ALB.

This project refactors [eks-portfolio-project-charlie](https://github.com/alexanderkachar/eks-portfolio-project-charlie): same GitOps and observability core, but with Gitea instead of GitHub, EKS Pod Identity instead of IRSA, External Secrets Operator for SSM-backed secrets, mirrored images in ECR, and VPC endpoints instead of node NAT egress.

## What It Demonstrates

- Private EKS API and private worker subnets with AWS access through VPC endpoints.
- Self-hosted Gitea server and Gitea Actions runner in service subnets.
- ArgoCD bootstrapped by Terraform and pointed at a single application repo on Gitea.
- ArgoCD Image Updater writing image tag bumps back to Git.
- External Secrets Operator reading SSM Parameter Store through Pod Identity.
- Public app ingress separated from internal ArgoCD, Grafana, and Gitea access.
- Scriptable spin-up, soft teardown, hard teardown, backup, restore, and VPN association toggles.

## Quick Start

Prerequisites: AWS credentials for the target account, Terraform, Helm, Docker, AWS CLI, Git, Curl, JQ, VPN certificates, and access to the S3 Terraform state bucket configured under `terraform/*/environments/dev`.

```bash
make spin-up
```

That applies infra, mirrors third-party images to ECR, bootstraps the Gitea express-app repository, mirrors Gitea Actions dependencies, and applies the platform layer.

## Deployment Sequence

The cold-start sequence is encoded in [scripts/spin-up.sh](scripts/spin-up.sh) and runs in this order:

1. **Assume the admin role.** so all subsequent commands see Terraform-capable AWS credentials.
2. **Apply the infra layer.** `terraform -chdir=terraform/infra/environments/dev apply` provisions VPC + endpoints, EKS (private API, nodes in private subnets), ECR repos, IAM Pod Identity roles, public + internal ALBs, Route 53 zones, Gitea server EC2 with persistent EBS, Gitea runner EC2, Client VPN, and the S3 config + backup buckets. If a prior soft-teardown saved an EBS volume ID in `.state/gitea-data-volume-id`, the script passes `gitea_data_volume_id=<id>` so the volume reattaches.
3. **Wait for Gitea boot.** The script polls SSM for `/fp-argo/gitea/runner-registration-token`, which is written by the Gitea EC2 user-data only after the server has booted and produced an admin API token. The runner EC2 polls the same parameter and self-registers once it appears.
4. **Mirror third-party images to ECR.** `scripts/mirror-images.sh` reads `scripts/images.yaml` and copies every image the platform layer references (ArgoCD, Image Updater, AWS LB Controller, ESO, kube-prometheus-stack, Loki, Promtail, supporting sidecars) into ECR. The cluster has no public internet egress, so this must complete before the platform Helm releases can pull.
5. **Bootstrap Gitea.** `scripts/bootstrap-gitea.sh` reads Terraform infra outputs + the Gitea admin API token from SSM, creates the `fp-argo` org and the single `express-app` repo, seeds it with [app/](app/) + [charts/express-app/](charts/express-app/) + the workflow file at [initial-manifests/express-app/.gitea/workflows/build.yaml](initial-manifests/express-app/.gitea/workflows/build.yaml) (with placeholders substituted), and creates two fine-grained PATs stored back in SSM: `/fp-argo/gitea/express-app-deploy-token` (read-only, used by ArgoCD) and `/fp-argo/gitea/express-app-writer-token` (read+write, used by Image Updater for the values-override.yaml writeback).
6. **Mirror Gitea Actions dependencies.** `scripts/mirror-actions.sh` mirrors `actions/checkout`, `docker/build-push-action`, `docker/login-action`, `aws-actions/configure-aws-credentials`, and `aws-actions/amazon-ecr-login` into Gitea so the runner can resolve them without public internet.
7. **Apply the platform layer.** `terraform -chdir=terraform/platform/environments/dev apply` reads the infra remote state and installs everything that runs on EKS: AWS Load Balancer Controller, External Secrets Operator + `ClusterSecretStore`, the observability umbrella (kube-prometheus-stack + Loki + Promtail), ArgoCD itself, ArgoCD Image Updater, then the [charts/argocd-bootstrap/](charts/argocd-bootstrap/) glue release that materializes the two repo-cred ExternalSecrets, binds ArgoCD to the internal ALB, and creates the single `express-app` Application CRD pointing at the Gitea repo.
8. **First end-to-end run.** A commit to the express-app repo on Gitea triggers the build workflow on the runner, which pushes `${ECR}/express-app:<sha>` and `:latest`. Image Updater detects the new tag via the ECR VPC endpoint, commits `image.tag` into `chart/values-override.yaml` on Gitea, ArgoCD reconciles, and the new revision is live on the public ALB at `app.alexanderkachar.com`.

Order is load-bearing in two places. Image mirroring (step 4) must finish before the platform Terraform apply (step 7), because ArgoCD, ESO, and the observability stack all pull from ECR. Gitea bootstrap (step 5) must finish before the platform apply, because the argocd-bootstrap chart's `Application` CRD references the Gitea express-app URL and the two SSM tokens it produces.

```bash
make teardown-soft
```

Backs up Gitea, destroys platform and infra compute, and preserves the Gitea data EBS volume for the next `make spin-up`.

```bash
CONFIRM_HARD_TEARDOWN=destroy-gitea-state make teardown-hard
```

Runs soft teardown, then deletes the preserved Gitea data volume.

## Main Entry Points

- [docs/architecture.md](docs/architecture.md) - architecture, networking, identity, GitOps flow, and diagram.
- [docs/runbook.md](docs/runbook.md) - operator procedures and troubleshooting.
- [docs/decisions](docs/decisions) - short ADR-style notes for the major design choices.
- [docs/blog/private-eks-gitops-draft.md](docs/blog/private-eks-gitops-draft.md) - portfolio blog post draft.
- [CLAUDE.md](CLAUDE.md) - original phase plan and implementation guide.

## Repository Map

- `app/` - Express demo application.
- `charts/express-app/` - application Helm chart; `values-override.yaml` is managed by ArgoCD Image Updater.
- `charts/observability/` - local umbrella chart for kube-prometheus-stack, Loki, Promtail, and dashboards.
- `terraform/infra/` - VPC, endpoints, EKS, ECR, IAM, ALBs, Route 53, Gitea, runner, VPN, and backup buckets.
- `terraform/platform/` - Helm-based platform layer: AWS Load Balancer Controller, ESO, observability (kube-prometheus-stack + Loki + Promtail), ArgoCD, Image Updater, and the argocd-bootstrap glue chart.
- `charts/argocd-bootstrap/` - applied as the final Helm release in the platform layer; contains the internal-ALB TargetGroupBinding, the two repo-cred ExternalSecrets, and the single express-app Application CRD.
- `initial-manifests/express-app/` - the Gitea Actions workflow seeded into the express-app repo on first bootstrap.
- `scripts/` - image mirroring, Gitea bootstrap, action mirroring, lifecycle, backup, restore, and VPN helper scripts.

## Honest Scope

This is intentionally portfolio-scaled. Gitea is single-instance EC2 with persistent EBS and S3 backups, not HA. ArgoCD and Grafana rely on VPN-level access rather than SSO. There is one dev environment. The architecture is designed to demonstrate production-grade patterns in a low-cost, short-lived lab environment, not to claim full production parity.
