variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the controller manages load balancers."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "ecr_registry_url" {
  description = "ECR registry URL prefix containing mirrored platform images."
  type        = string
}

variable "pod_identity_role_arn" {
  description = "IAM role ARN associated with the controller service account via EKS Pod Identity."
  type        = string
}

variable "chart_version" {
  description = "AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "1.13.0"
}

variable "image_tag" {
  description = "Mirrored AWS Load Balancer Controller image tag."
  type        = string
  default     = "v2.13.0"
}
