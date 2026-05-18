variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD and Image Updater."
  type        = string
  default     = "argocd"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "ecr_registry_url" {
  description = "ECR registry URL prefix containing mirrored platform images."
  type        = string
}

variable "argocd_target_group_arn" {
  description = "ALB target group ARN for the ArgoCD TargetGroupBinding."
  type        = string
}

variable "platform_manifests_repo_url" {
  description = "Gitea HTTPS clone URL for the platform-manifests repository."
  type        = string
}

variable "gitea_username" {
  description = "Gitea username used by ArgoCD repository credentials."
  type        = string
}

variable "platform_deploy_token_ssm_name" {
  description = "SSM parameter name holding the platform-manifests deploy token."
  type        = string
}

variable "application_controller_role_arn" {
  description = "Pod Identity role ARN for the ArgoCD application controller."
  type        = string
}

variable "image_updater_role_arn" {
  description = "Pod Identity role ARN for ArgoCD Image Updater."
  type        = string
}

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

variable "argocd_image_tag" {
  description = "Mirrored ArgoCD image tag."
  type        = string
  default     = "v2.14.9"
}

variable "dex_image_tag" {
  description = "Mirrored Dex image tag."
  type        = string
  default     = "v2.42.0"
}

variable "redis_image_tag" {
  description = "Mirrored Redis image tag."
  type        = string
  default     = "7.4.2-alpine"
}

variable "image_updater_image_tag" {
  description = "Mirrored ArgoCD Image Updater image tag."
  type        = string
  default     = "v0.16.0"
}
