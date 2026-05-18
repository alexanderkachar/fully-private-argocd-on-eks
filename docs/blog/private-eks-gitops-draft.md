# Running Private EKS GitOps With No Public Internet For The Cluster

## Working Title

Running ArgoCD on a private EKS cluster with internal Git, internal CI, and no node internet egress

## Hook

Most EKS GitOps demos quietly depend on public internet access: GitHub webhooks, public container registries, NAT-backed image pulls, and public admin endpoints. I wanted to build the opposite: a private EKS platform where the cluster cannot reach the public internet, but the developer workflow still feels complete.

## What I Built

This project provisions a private EKS platform with Terraform:

- EKS API endpoint is private.
- Worker nodes live in private subnets with no NAT route.
- AWS API access goes through VPC endpoints.
- All platform images are mirrored into ECR.
- Git hosting runs inside the VPC on Gitea.
- CI runs inside the VPC on Gitea Actions.
- ArgoCD syncs from Gitea.
- External Secrets Operator pulls credentials from SSM Parameter Store.
- Admin access is through AWS Client VPN.
- The demo Express app is the only public endpoint.

## Motivation

The previous version of this portfolio project used GitHub Actions and a more public-friendly architecture. That was useful, but it skipped the hard part of private platform design: what breaks when your cluster cannot pull from the internet?

The answer is: a lot. Helm charts can still be fetched by Terraform from an operator laptop, but every runtime image needs to exist in ECR. Git credentials need to arrive without pasting secrets into Terraform. Internal dashboards need routing that does not expose admin tools publicly. CI needs a trust model that does not depend on GitHub OIDC.

## Architecture Summary

The VPC has public, private, and services subnet tiers.

Private subnets host EKS nodes and the internal ALB. They reach AWS through VPC endpoints only. Services subnets host Gitea and the runner; they keep NAT because the bootstrap process still needs to mirror upstream dependencies. Public subnets host the public app ALB and Client VPN association.

The GitOps flow is:

1. Push app code to Gitea.
2. Gitea Actions builds and pushes an image to ECR.
3. ArgoCD Image Updater finds the new ECR tag.
4. Image Updater commits a Helm values update back to Gitea.
5. ArgoCD syncs the app.

## What Was Hard

The hardest part was not EKS itself. It was closing every quiet public dependency.

Helm chart installation is only half the story. The chart can be public if Terraform runs from a laptop with internet, but the images rendered by the chart cannot be public if pods run in private subnets without NAT. That forced a declarative image mirror manifest and ECR repository set.

The second hard part was lifecycle. A portfolio project should be destroyable at the end of the day. But if Gitea is the source of truth, destroying it casually is painful. The compromise is soft teardown: back up Gitea, preserve the data EBS volume, and destroy compute.

## What I Would Change In Real Production

I would not run production Git on one EC2 instance with SQLite. I would use HA Git hosting, an external database, object storage, and formal backup restore tests.

I would add SSO for ArgoCD and Grafana instead of relying on VPN-only access. I would also split dev, staging, and production environments and add promotion workflows instead of a single dev environment.

Finally, I would make the image mirror pipeline continuous. For the portfolio version, mirroring is a script because the goal is to show the dependency boundary clearly.

## Why This Is Still Useful

This project is not trying to be production by pretending away tradeoffs. It is useful because it exposes the design pressure of private Kubernetes platforms:

- identity boundaries,
- network egress boundaries,
- image supply chain boundaries,
- secret delivery boundaries,
- and teardown/restore boundaries.

That is the part I wanted to practice.
