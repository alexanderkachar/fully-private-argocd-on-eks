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
  description = "VPC CIDR."
  type        = string
}

variable "subnet_id" {
  description = "Services subnet (single AZ — the runner is stateless so AZ choice is incidental)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. CI workloads run inside Docker on this host."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root volume size — needs headroom for docker layer cache and act_runner workspace."
  type        = number
  default     = 30
}

variable "runner_version" {
  description = "Gitea act_runner image tag."
  type        = string
  default     = "0.2.11"
}

variable "gitea_instance_url" {
  description = "Internal URL the runner uses to reach Gitea (e.g. https://gitea.alexanderkachar.com)."
  type        = string
}

variable "config_bucket_name" {
  description = "S3 bucket holding the rendered runner docker-compose and config."
  type        = string
}

variable "config_bucket_arn" {
  description = "Config bucket ARN."
  type        = string
}

variable "runner_token_ssm_name" {
  description = "SSM Parameter Store name holding the Gitea runner registration token (SecureString)."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the runner is allowed to push to."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name (for runner-side kubectl from workflows)."
  type        = string
}

variable "cluster_arn" {
  description = "EKS cluster ARN to scope DescribeCluster."
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS cluster SG; the runner is granted 443 ingress for kubectl against the private API."
  type        = string
}
