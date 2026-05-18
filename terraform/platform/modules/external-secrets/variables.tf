variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "region" {
  description = "AWS region used by the ClusterSecretStore."
  type        = string
}

variable "ecr_registry_url" {
  description = "ECR registry URL prefix containing mirrored platform images."
  type        = string
}

variable "pod_identity_role_arn" {
  description = "IAM role ARN associated with the External Secrets controller service account."
  type        = string
}

variable "namespace" {
  description = "Namespace for External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "chart_version" {
  description = "External Secrets Operator Helm chart version."
  type        = string
  default     = "0.14.0"
}

variable "image_tag" {
  description = "Mirrored External Secrets Operator image tag."
  type        = string
  default     = "v0.14.0"
}
