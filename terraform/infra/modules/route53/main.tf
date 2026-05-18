locals {
  domain_name             = trimsuffix(var.domain_name, ".")
  certificate_domain_name = coalesce(var.certificate_domain_name, "*.${local.domain_name}")
  app_hostname            = "${var.app_subdomain}.${local.domain_name}"
  grafana_hostname        = "${var.grafana_subdomain}.${local.domain_name}"
  argocd_hostname         = "${var.argocd_subdomain}.${local.domain_name}"
  gitea_hostname          = "${var.gitea_subdomain}.${local.domain_name}"
}

data "aws_route53_zone" "public" {
  name         = "${local.domain_name}."
  private_zone = false
}

data "aws_acm_certificate" "wildcard" {
  domain      = local.certificate_domain_name
  statuses    = ["ISSUED"]
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

# Private hosted zone for the same domain, scoped to the VPC. Resolves
# argocd/grafana/gitea hostnames to the internal ALB for in-VPC consumers
# and for operators on the Client VPN (VPN gets DNS through the VPC
# resolver). The public zone keeps owning app.<domain> for internet users.
resource "aws_route53_zone" "private" {
  name = local.domain_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = local.domain_name
  }
}
