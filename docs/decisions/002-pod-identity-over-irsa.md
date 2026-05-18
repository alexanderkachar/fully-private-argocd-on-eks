# 002 - EKS Pod Identity Over IRSA

## Status

Accepted

## Context

In-cluster controllers need AWS permissions: AWS Load Balancer Controller, External Secrets Operator, ArgoCD Image Updater, ArgoCD application controller, and EBS CSI.

## Decision

Use EKS Pod Identity for pod-to-IAM role binding.

## Consequences

Pod Identity removes the need to manage an IAM OIDC provider and IRSA trust policies for each service account. The Terraform shape is easier to read: create IAM role, install service account, associate role to service account.

The tradeoff is portability. IRSA is more familiar across older EKS setups and some platform teams already standardize on it. This project favors the newer native EKS path because the platform is built from scratch.
