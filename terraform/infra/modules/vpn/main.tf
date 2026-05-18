locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ----- Self-signed PKI -----

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${local.name_prefix}-vpn-ca"
    organization = var.project_name
  }

  is_ca_certificate     = true
  validity_period_hours = 8760 * 5 # 5 years

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# Server cert
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "${local.name_prefix}-vpn-server"
    organization = var.project_name
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 * 2 # 2 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Client cert (one operator)
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = var.client_username
    organization = var.project_name
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 * 2

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

# ----- ACM imports -----
# Mutual auth requires both certs to live in ACM (in the same region as the
# VPN endpoint) and both must include the CA chain.

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = {
    Name = "${local.name_prefix}-vpn-server"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "client" {
  private_key       = tls_private_key.client.private_key_pem
  certificate_body  = tls_locally_signed_cert.client.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = {
    Name = "${local.name_prefix}-vpn-client"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ----- Client VPN endpoint -----

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/clientvpn/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${local.name_prefix}-vpn-logs"
  }
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

resource "aws_security_group" "vpn" {
  name        = "${local.name_prefix}-vpn-sg"
  description = "Client VPN endpoint network interfaces."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow VPN ENIs to reach anything inside the VPC."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-vpn-sg"
  }
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${local.name_prefix} operator VPN."
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.client_cidr_block

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  # Split tunnel: only VPC traffic flows over the VPN. The operator keeps
  # their local default route, which is what we want for a part-time admin
  # tunnel (no laptop egress through AWS).
  split_tunnel = true

  vpc_id             = var.vpc_id
  security_group_ids = [aws_security_group.vpn.id]

  dns_servers = []

  tags = {
    Name = "${local.name_prefix}-vpn"
  }
}

resource "aws_ec2_client_vpn_network_association" "this" {
  count = var.associated ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.association_subnet_id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  count = var.associated ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow VPN clients to reach the entire VPC."
}
