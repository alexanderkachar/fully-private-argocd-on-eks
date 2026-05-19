variable "region" {
  description = "AWS region. Must match the infra layer."
  type        = string
  default     = "us-east-1"
}

variable "gitea_org" {
  description = "Gitea organization containing the express-app repository."
  type        = string
  default     = "fp-argo"
}

variable "express_app_deploy_token_ssm_name" {
  description = "SSM parameter name holding the read-only Gitea token ArgoCD uses to fetch the express-app chart. Created by bootstrap-gitea.sh."
  type        = string
  default     = "/fp-argo/gitea/express-app-deploy-token"
}

variable "express_app_writer_token_ssm_name" {
  description = "SSM parameter name holding the read+write Gitea token Image Updater uses to commit values-override.yaml. Created by bootstrap-gitea.sh."
  type        = string
  default     = "/fp-argo/gitea/express-app-writer-token"
}
