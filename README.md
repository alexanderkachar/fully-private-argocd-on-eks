# Fully Private ArgoCD on EKS

A portfolio-scale Amazon EKS platform where the cluster has no public internet egress, GitOps runs through ArgoCD, CI/CD lives inside the VPC on self-hosted Gitea, and operator access is gated through AWS Client VPN. The Express demo app is the only public workload, exposed through a separate internet-facing ALB.

This project refactors [eks-portfolio-project-charlie](https://github.com/alexanderkachar/eks-portfolio-project-charlie): same GitOps and observability core, but with Gitea instead of GitHub, EKS Pod Identity instead of IRSA, External Secrets Operator for SSM-backed secrets, mirrored images in ECR, and VPC endpoints instead of node NAT egress.

## What It Demonstrates

- Private EKS API and private worker subnets with AWS access through VPC endpoints.
- Self-hosted Gitea server and Gitea Actions runner in service subnets.
- ArgoCD app-of-apps bootstrap from Gitea.
- ArgoCD Image Updater writing image tag bumps back to Git.
- External Secrets Operator reading SSM Parameter Store through Pod Identity.
- Public app ingress separated from internal ArgoCD, Grafana, and Gitea access.
- Scriptable spin-up, soft teardown, hard teardown, backup, restore, and VPN association toggles.

## Quick Start

Prerequisites: AWS credentials for the target account, Terraform, Helm, Docker, AWS CLI, Git, Curl, JQ, VPN certificates, and access to the S3 Terraform state bucket configured under `terraform/*/environments/dev`.

```bash
make spin-up
```

That applies infra, mirrors third-party images to ECR, bootstraps Gitea repositories, mirrors Gitea Actions dependencies, and applies the platform layer.

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
- `terraform/platform/` - Helm-based platform layer: AWS Load Balancer Controller, ESO, ArgoCD, and Image Updater.
- `initial-manifests/` - bootstrap content pushed into Gitea repositories.
- `scripts/` - image mirroring, Gitea bootstrap, action mirroring, lifecycle, backup, restore, and VPN helper scripts.

## Honest Scope

This is intentionally portfolio-scaled. Gitea is single-instance EC2 with persistent EBS and S3 backups, not HA. ArgoCD and Grafana rely on VPN-level access rather than SSO. There is one dev environment. The architecture is designed to demonstrate production-grade patterns in a low-cost, short-lived lab environment, not to claim full production parity.
