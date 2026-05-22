output "instance_id" {
  description = "Gitea runner EC2 instance ID."
  value       = aws_instance.this.id
}

output "ready_ssm_name" {
  description = "Per-instance SSM parameter written when the runner bootstrap is ready."
  value       = "${local.runner_ready_ssm_prefix}/${aws_instance.this.id}"
}

output "iam_role_arn" {
  description = "IAM role ARN used by the runner. Granted EKS cluster admin via access entry."
  value       = aws_iam_role.this.arn
}

output "security_group_id" {
  description = "Runner security group ID."
  value       = aws_security_group.this.id
}

output "ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the Gitea runner."
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${data.aws_region.current.name}"
}
