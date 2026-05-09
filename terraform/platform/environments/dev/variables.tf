variable "region" {
  description = "AWS region. Must match the infra layer."
  type        = string
  default     = "us-east-1"
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
  description = "SSM parameter name holding the GitHub PAT used by ArgoCD Image Updater for Git write-back."
  type        = string
}
