variable "domain_name" {
  description = "Existing public Route 53 domain name. A private hosted zone for the same name is created and attached to the VPC."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the private hosted zone is associated with."
  type        = string
}

variable "app_subdomain" {
  description = "Subdomain used by the Express app (public)."
  type        = string
  default     = "app"
}

variable "grafana_subdomain" {
  description = "Subdomain used by Grafana (internal)."
  type        = string
  default     = "grafana"
}

variable "argocd_subdomain" {
  description = "Subdomain used by ArgoCD (internal)."
  type        = string
  default     = "argocd"
}

variable "gitea_subdomain" {
  description = "Subdomain used by Gitea (internal)."
  type        = string
  default     = "gitea"
}

variable "certificate_domain_name" {
  description = "Existing ACM wildcard certificate domain name. Defaults to *.<domain>."
  type        = string
  default     = null
}
