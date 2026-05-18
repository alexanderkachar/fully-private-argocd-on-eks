output "instance_id" {
  description = "Gitea EC2 instance ID."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Gitea EC2 private IP."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Gitea EC2 security group ID (consumed by the runner SG for SSH ingress, if enabled later)."
  value       = aws_security_group.this.id
}

output "admin_username" {
  description = "Gitea admin username."
  value       = local.admin_username
}

output "admin_password_ssm_name" {
  description = "SSM parameter name holding the Gitea admin password (SecureString)."
  value       = aws_ssm_parameter.admin_password.name
}

output "admin_api_token_ssm_name" {
  description = "SSM parameter name where user_data writes the admin API token after first boot. Read by the bootstrap script."
  value       = "${local.ssm_prefix}/admin-api-token"
}

output "runner_token_ssm_name" {
  description = "SSM parameter name where user_data writes the runner registration token. Read by gitea-runner user_data."
  value       = "${local.ssm_prefix}/runner-registration-token"
}

output "data_volume_id" {
  description = "Persistent data EBS volume ID."
  value       = aws_ebs_volume.data.id
}

output "ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the Gitea server."
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${data.aws_region.current.name}"
}
