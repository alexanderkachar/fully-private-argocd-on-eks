variable "region" {
  description = "AWS region. Must match the infra layer."
  type        = string
  default     = "us-east-1"
}

variable "gitea_org" {
  description = "Gitea organization containing the platform-manifests repository."
  type        = string
  default     = "fp-argo"
}

variable "platform_deploy_token_ssm_name" {
  description = "SSM parameter name holding the platform-manifests deploy token created by bootstrap-gitea.sh."
  type        = string
  default     = "/fp-argo/gitea/platform-deploy-token"
}
