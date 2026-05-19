variable "namespace" {
  description = "Kubernetes namespace for the observability stack."
  type        = string
  default     = "observability"
}

variable "ecr_registry_url" {
  description = "ECR registry URL prefix containing mirrored observability images."
  type        = string
}

variable "grafana_target_group_arn" {
  description = "Internal ALB target group ARN for Grafana."
  type        = string
}

variable "release_name" {
  description = "Helm release name. Drives the Grafana service name and Loki gateway DNS."
  type        = string
  default     = "observability"
}
