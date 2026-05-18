# 003 - VPC Endpoints Over NAT For Cluster Nodes

## Status

Accepted

## Context

The main architectural goal is a cluster with no public internet egress. EKS nodes still need AWS APIs for image pulls, logs, SSM, ELB registration, STS, and EKS authentication.

## Decision

Private EKS subnets do not route through NAT. AWS API access is provided through interface VPC endpoints plus an S3 gateway endpoint.

## Consequences

This makes the airgap story clear: platform images must be mirrored to ECR, and cluster workloads cannot silently pull from the public internet.

The tradeoff is operational strictness. Missing endpoint coverage or missing mirrored images cause visible failures. That is intentional for this project, but production would add monitoring around endpoint health and mirror freshness.
