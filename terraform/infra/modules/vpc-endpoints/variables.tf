variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where endpoints are attached."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; used to scope the endpoint security group ingress."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs hosting the interface endpoint ENIs."
  type        = list(string)
}

variable "route_table_ids" {
  description = "Route table IDs the S3 gateway endpoint is attached to. Typically the private + services tables."
  type        = list(string)
}

variable "interface_endpoint_services" {
  description = "Interface endpoint service short names. Each becomes com.amazonaws.<region>.<name>."
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "eks",
    "eks-auth",
    "sts",
    "ec2",
    "elasticloadbalancing",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "logs",
  ]
}
