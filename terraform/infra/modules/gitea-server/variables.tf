variable "project_name" {
  description = "Short project identifier."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; allowed to reach Gitea on 3000/tcp."
  type        = string
}

variable "vpn_client_cidr" {
  description = "Client VPN CIDR; allowed to reach Gitea on 3000/tcp for operator access."
  type        = string
}

variable "subnet_id" {
  description = "Services subnet ID (single AZ) where Gitea EC2 lives."
  type        = string
}

variable "availability_zone" {
  description = "AZ for the persistent EBS data volume — must match the subnet."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size."
  type        = number
  default     = 8
}

variable "data_volume_size_gb" {
  description = "Data EBS volume size (mounted at /opt/gitea)."
  type        = number
  default     = 20
}

variable "gitea_version" {
  description = "Gitea container image tag."
  type        = string
  default     = "1.22.3"
}

variable "gitea_hostname" {
  description = "Public-facing hostname for Gitea (e.g. gitea.alexanderkachar.com). Used as ROOT_URL inside the container."
  type        = string
}

variable "config_bucket_name" {
  description = "S3 bucket holding rendered docker-compose templates."
  type        = string
}

variable "config_bucket_arn" {
  description = "Config bucket ARN."
  type        = string
}

variable "backup_bucket_name" {
  description = "S3 bucket where the daily Gitea dump cron writes."
  type        = string
}

variable "backup_bucket_arn" {
  description = "Backup bucket ARN."
  type        = string
}

variable "alb_target_group_arn" {
  description = "Internal ALB Gitea target group ARN; the instance is registered as an instance target."
  type        = string
}
