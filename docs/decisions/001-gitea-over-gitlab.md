# 001 - Gitea Over GitLab

## Status

Accepted

## Context

The platform needs a private Git host and CI runner inside the VPC. The project is portfolio-scale and optimized for short work sessions, quick teardown, and low idle cost.

## Decision

Use Gitea on a single EC2 instance with a Gitea Actions runner on a second EC2 instance.

## Consequences

Gitea is lightweight, fast to bootstrap, easy to back up with `gitea dump`, and simple enough to run on EC2 with SQLite for this lab. It also supports Actions-style workflows, so the CI/CD story stays familiar.

The tradeoff is availability. This is not HA Git hosting. In production, this would be replaced with a managed Git service, GitLab with external Postgres, or Gitea on Kubernetes with HA storage and database dependencies.
