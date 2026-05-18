output "load_balancer_arn" {
  description = "Internal application load balancer ARN."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "Internal application load balancer DNS name."
  value       = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  description = "Internal ALB Route 53 alias zone ID."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "Internal ALB security group ID."
  value       = aws_security_group.this.id
}

output "argocd_target_group_arn" {
  description = "Target group ARN for the ArgoCD TargetGroupBinding."
  value       = aws_lb_target_group.argocd.arn
}

output "grafana_target_group_arn" {
  description = "Target group ARN for the Grafana TargetGroupBinding."
  value       = aws_lb_target_group.grafana.arn
}

output "gitea_target_group_arn" {
  description = "Target group ARN for the Gitea EC2 attachment."
  value       = aws_lb_target_group.gitea.arn
}
