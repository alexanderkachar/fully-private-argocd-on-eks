variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version."
  type        = string
  default     = "7.8.23"
}

variable "image_updater_chart_version" {
  description = "ArgoCD Image Updater Helm chart version."
  type        = string
  default     = "0.12.1"
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD and Image Updater."
  type        = string
  default     = "argocd"
}

variable "argocd_target_group_arn" {
  description = "ALB target group ARN for the ArgoCD TargetGroupBinding."
  type        = string
}

variable "github_owner" {
  description = "GitHub owner (user or org) of the application repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner prefix)."
  type        = string
}

variable "pat_ssm_parameter_name" {
  description = "SSM parameter name holding the GitHub PAT for Image Updater Git write-back."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}
