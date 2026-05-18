variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the internal load balancer is created."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs hosting the internal ALB."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR; allowed to reach the internal ALB on 443."
  type        = string
}

variable "vpn_client_cidr" {
  description = "Client VPN client CIDR block; allowed to reach the internal ALB on 443. Operators come through the VPN."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group attached to EKS nodes/pod ENIs that should accept ALB traffic."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN used by the HTTPS listener (wildcard covering argocd/grafana/gitea hostnames)."
  type        = string
}

variable "hosted_zone_id" {
  description = "Private Route 53 hosted zone ID where the per-service A-records are written."
  type        = string
}

variable "argocd_hostname" {
  description = "Internal DNS hostname for ArgoCD (e.g. argocd.alexanderkachar.com)."
  type        = string
}

variable "grafana_hostname" {
  description = "Internal DNS hostname for Grafana."
  type        = string
}

variable "gitea_hostname" {
  description = "Internal DNS hostname for Gitea."
  type        = string
}

variable "argocd_target_port" {
  description = "ArgoCD server pod port (HTTP, insecure mode — TLS terminated at ALB)."
  type        = number
  default     = 8080
}

variable "argocd_health_check_path" {
  description = "HTTP path used by the ArgoCD target group health check."
  type        = string
  default     = "/healthz"
}

variable "grafana_target_port" {
  description = "Grafana pod port."
  type        = number
  default     = 3000
}

variable "grafana_health_check_path" {
  description = "HTTP path used by the Grafana target group health check."
  type        = string
  default     = "/api/health"
}

variable "gitea_target_port" {
  description = "Gitea HTTP port on the EC2 instance."
  type        = number
  default     = 3000
}

variable "gitea_health_check_path" {
  description = "HTTP path used by the Gitea target group health check."
  type        = string
  default     = "/api/healthz"
}
