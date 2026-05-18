output "load_balancer_arn" {
  description = "Public application load balancer ARN."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "Public application load balancer DNS name."
  value       = aws_lb.this.dns_name
}

output "security_group_id" {
  description = "Public application load balancer security group ID."
  value       = aws_security_group.this.id
}

output "target_group_arn" {
  description = "App target group ARN for the express-app TargetGroupBinding."
  value       = aws_lb_target_group.this.arn
}
