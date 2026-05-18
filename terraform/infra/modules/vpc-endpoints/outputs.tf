output "security_group_id" {
  description = "Security group attached to the interface endpoint ENIs."
  value       = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  description = "Map of interface endpoint service name to endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint ID."
  value       = aws_vpc_endpoint.s3.id
}
