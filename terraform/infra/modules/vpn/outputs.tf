output "endpoint_id" {
  description = "Client VPN endpoint ID."
  value       = aws_ec2_client_vpn_endpoint.this.id
}

output "client_cidr_block" {
  description = "Client VPN client CIDR. Used by other modules to allow VPN-sourced traffic in security groups."
  value       = var.client_cidr_block
}

output "associated" {
  description = "Whether the endpoint is currently associated with a subnet (i.e. billable)."
  value       = var.associated
}

output "ca_cert_pem" {
  description = "Self-signed CA certificate. Embedded in the client OpenVPN config."
  value       = tls_self_signed_cert.ca.cert_pem
}

output "client_cert_pem" {
  description = "Client certificate. Embedded in the client OpenVPN config."
  value       = tls_locally_signed_cert.client.cert_pem
}

output "client_private_key_pem" {
  description = "Client private key. Embedded in the client OpenVPN config. Sensitive — only retrieve via `terraform output -raw`."
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}
