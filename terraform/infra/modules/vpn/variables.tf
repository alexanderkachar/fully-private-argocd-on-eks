variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC the Client VPN endpoint terminates into."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; used in the authorization rule so VPN clients can reach in-VPC resources."
  type        = string
}

variable "association_subnet_id" {
  description = "Subnet ID the VPN endpoint is associated with when var.associated = true. Single AZ is fine for a portfolio project."
  type        = string
}

variable "associated" {
  description = "When true, create the network association + authorization rule (the parts that cost $0.10/hour). Toggle off via Makefile target while not actively working."
  type        = bool
  default     = true
}

variable "client_cidr_block" {
  description = "CIDR block VPN clients draw their IPs from. Must be /22 or larger and not overlap with the VPC."
  type        = string
  default     = "10.100.0.0/22"
}

variable "server_dns_name" {
  description = "FQDN placed in the Client VPN server certificate DNS SAN for ACM."
  type        = string
}

variable "client_username" {
  description = "Common Name embedded in the single client certificate. Used as the identifier in the OpenVPN config."
  type        = string
  default     = "operator"
}

variable "cloudwatch_log_retention_days" {
  description = "Retention for the Client VPN connection log group."
  type        = number
  default     = 7
}
