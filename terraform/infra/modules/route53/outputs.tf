output "domain_name" {
  description = "Route 53 domain name."
  value       = local.domain_name
}

output "public_hosted_zone_id" {
  description = "Existing public hosted zone ID."
  value       = data.aws_route53_zone.public.zone_id
}

output "public_hosted_zone_arn" {
  description = "Existing public hosted zone ARN."
  value       = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.public.zone_id}"
}

output "private_hosted_zone_id" {
  description = "Private hosted zone ID (in-VPC resolution for admin services)."
  value       = aws_route53_zone.private.zone_id
}

output "private_hosted_zone_arn" {
  description = "Private hosted zone ARN."
  value       = aws_route53_zone.private.arn
}

output "certificate_arn" {
  description = "Wildcard ACM certificate ARN used by both public and internal ALBs."
  value       = data.aws_acm_certificate.wildcard.arn
}

output "app_hostname" {
  description = "Public hostname for the Express app."
  value       = local.app_hostname
}

output "grafana_hostname" {
  description = "Internal hostname for Grafana."
  value       = local.grafana_hostname
}

output "argocd_hostname" {
  description = "Internal hostname for ArgoCD."
  value       = local.argocd_hostname
}

output "gitea_hostname" {
  description = "Internal hostname for Gitea."
  value       = local.gitea_hostname
}
