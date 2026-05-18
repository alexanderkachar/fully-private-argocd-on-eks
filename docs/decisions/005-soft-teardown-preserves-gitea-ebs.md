# 005 - Soft Teardown Preserves Gitea EBS

## Status

Accepted

## Context

The environment is expected to run for work sessions and then be destroyed. Gitea history should survive teardown without keeping EC2 instances online.

## Decision

Soft teardown backs up Gitea to S3, saves the Gitea data EBS volume ID under `.state/`, removes that volume from Terraform state, and destroys the rest of infra. The next spin-up passes the volume ID back into Terraform and reattaches it.

## Consequences

Idle cost stays low while preserving working Git state. S3 backups provide a second recovery path.

The tradeoff is state choreography. Removing a resource from Terraform state is deliberate here, but it needs to be documented and scripted carefully. Production would use a managed database and object storage instead of EC2-local SQLite on EBS.
