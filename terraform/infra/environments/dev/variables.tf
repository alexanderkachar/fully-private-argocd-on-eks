variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "admin_principal_arn" {
  description = "IAM principal ARN granted cluster-admin via access entry (e.g. the ARN of the IAM user or role you run terraform / kubectl as)."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "github_owner" {
  description = "GitHub owner (user or org) for the repo the runner registers against."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for the self-hosted runner registration. Use only the repo name, without the owner prefix."
  type        = string
}

variable "domain_name" {
  description = "Existing public Route 53 domain name."
  type        = string
  default     = "alexanderkachar.com"
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
  description = "Existing ACM certificate domain name used by both ALBs."
  type        = string
  default     = "*.alexanderkachar.com"
}

variable "vpn_associated" {
  description = "When true, associate the Client VPN endpoint with a subnet and create the authorization rule (billable). Toggle off when not actively working to save the per-hour cost."
  type        = bool
  default     = true
}

variable "vpn_client_cidr" {
  description = "CIDR block VPN clients draw their IPs from. Must not overlap with the VPC."
  type        = string
  default     = "10.100.0.0/22"
}
