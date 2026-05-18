output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered [AZ-a, AZ-b]."
  value       = [aws_subnet.this["public_a"].id, aws_subnet.this["public_b"].id]
}

output "services_subnet_ids" {
  description = "Services subnet IDs (Gitea server + runner), ordered [AZ-a, AZ-b]."
  value       = [aws_subnet.this["services_a"].id, aws_subnet.this["services_b"].id]
}

output "services_subnet_azs" {
  description = "Availability zones for the services subnets, ordered [AZ-a, AZ-b]. Consumed by gitea-server to place the persistent EBS volume in the matching AZ."
  value       = [aws_subnet.this["services_a"].availability_zone, aws_subnet.this["services_b"].availability_zone]
}

output "private_subnet_ids" {
  description = "Private (cluster) subnet IDs, ordered [AZ-a, AZ-b]."
  value       = [aws_subnet.this["private_a"].id, aws_subnet.this["private_b"].id]
}

output "private_route_table_ids" {
  description = "Private subnet route table IDs. Consumed by the vpc-endpoints module to attach the S3 gateway endpoint."
  value       = [aws_route_table.private.id]
}

output "services_route_table_ids" {
  description = "Services subnet route table IDs. Consumed by the vpc-endpoints module to attach the S3 gateway endpoint."
  value       = [aws_route_table.services.id]
}
