# 004 - External Secrets Operator Over Secrets Store CSI Driver

## Status

Accepted

## Context

ArgoCD and Image Updater need Kubernetes `Secret` objects for repository credentials. The source of truth for secret values is SSM Parameter Store.

## Decision

Use External Secrets Operator to sync SSM parameters into Kubernetes Secrets.

## Consequences

ESO creates native Kubernetes Secrets that ArgoCD already understands, including repository credential secrets labeled with `argocd.argoproj.io/secret-type=repository`. This keeps the ArgoCD integration simple.

The tradeoff is that secret values exist as Kubernetes Secrets after sync. Secrets Store CSI Driver can mount values without creating native Secrets, but it is a worse fit for ArgoCD repository credential discovery.
