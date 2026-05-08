variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used to authenticate helm against the private endpoint."
  type        = string
}

variable "ecr_repository" {
  description = "ECR repository name for the packaged observability chart (e.g. 'observability')."
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry URL (account_id.dkr.ecr.region.amazonaws.com)."
  type        = string
}

variable "chart_dir" {
  description = "Absolute path to the observability Helm chart directory."
  type        = string
}

variable "grafana_target_group_arn" {
  description = "NLB/ALB target group ARN for the Grafana TargetGroupBinding."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into."
  type        = string
  default     = "observability"
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "observability"
}
