# Fully Private ArgoCD on EKS

A fully private Amazon EKS platform: the cluster is airgapped from the public internet, CI/CD lives inside the VPC on self-hosted Gitea, and operator access is gated through AWS Client VPN. The deployed Express application is the only resource reachable from the public internet, via a separate public-facing ALB.

This project is a refactor of [eks-portfolio-project-charlie](https://github.com/alexanderkachar/eks-portfolio-project-charlie). It keeps the GitOps and observability story, swaps GitHub for self-hosted Gitea, makes the cluster airgapped (VPC endpoints, no NAT egress from cluster nodes), and gates operator access behind VPN.

## Operator model

Portfolio project, not a long-running service. Expected lifecycle: spin up for a working session, `terraform destroy` at end of session, persistent state preserved on EBS and backed up to S3.

- Cold-start target: 15-20 minutes
- Teardown target: 5 minutes

## Quick start

```bash
make spin-up        # bring up infra + platform from scratch
make teardown-soft  # destroy compute, preserve Gitea EBS + S3 backups
make teardown-hard  # destroy everything including EBS (uses S3 backup to restore)
make restore        # restore Gitea state from S3 (invoked automatically by spin-up when needed)
```

## Documentation

- [CLAUDE.md](CLAUDE.md) — full project plan and phase-by-phase implementation guide
- `docs/architecture.md` — detailed architecture write-up (Phase 8)
- `docs/runbook.md` — operational procedures (Phase 8)
- `docs/decisions/` — ADR-style records of key choices (Phase 8)
