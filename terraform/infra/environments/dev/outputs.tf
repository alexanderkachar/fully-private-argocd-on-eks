output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "region" {
  description = "AWS region for this environment."
  value       = var.region
}

output "private_subnet_ids" {
  description = "Private (cluster) subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (private)."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_ca_data" {
  description = "Base64-encoded cluster CA. Required by dev-platform to configure the helm provider."
  value       = module.eks.cluster_ca_data
}

output "app_target_group_arn" {
  description = "Express app ALB target group ARN. Required by dev-platform for the app TargetGroupBinding."
  value       = module.alb_public.target_group_arn
}

output "argocd_target_group_arn" {
  description = "Internal ALB ArgoCD target group ARN. Required by dev-platform for the TargetGroupBinding."
  value       = module.alb_internal.argocd_target_group_arn
}

output "grafana_target_group_arn" {
  description = "Internal ALB Grafana target group ARN. Required by dev-platform for the TargetGroupBinding."
  value       = module.alb_internal.grafana_target_group_arn
}

output "gitea_target_group_arn" {
  description = "Internal ALB Gitea target group ARN. Phase 2 attaches the Gitea EC2 instance here."
  value       = module.alb_internal.gitea_target_group_arn
}

output "ecr_registry_url" {
  description = "ECR registry URL prefix (account.dkr.ecr.region.amazonaws.com). Used by scripts/mirror-images.sh."
  value       = module.ecr.registry_url
}

output "load_balancer_controller_role_arn" {
  description = "Pod Identity role ARN for AWS Load Balancer Controller. Consumed by the platform layer."
  value       = module.iam.load_balancer_controller_role_arn
}

output "external_secrets_role_arn" {
  description = "Pod Identity role ARN for External Secrets Operator. Consumed by the platform layer."
  value       = module.iam.external_secrets_role_arn
}

output "argocd_application_controller_role_arn" {
  description = "Pod Identity role ARN for ArgoCD application controller. Consumed by the platform layer."
  value       = module.iam.argocd_application_controller_role_arn
}

output "argocd_image_updater_role_arn" {
  description = "Pod Identity role ARN for ArgoCD Image Updater. Consumed by the platform layer."
  value       = module.iam.argocd_image_updater_role_arn
}

output "app_ecr_image_uri" {
  description = "Full ECR image URI for the Express app (without tag). Required by dev-platform for Image Updater."
  value       = "${module.ecr.registry_url}/${local.app_ecr_repository_name}"
}

output "argocd_hostname" {
  description = "Internal hostname for ArgoCD."
  value       = module.route53.argocd_hostname
}

output "grafana_hostname" {
  description = "Internal hostname for Grafana."
  value       = module.route53.grafana_hostname
}

output "gitea_hostname" {
  description = "Internal hostname for Gitea."
  value       = module.route53.gitea_hostname
}

output "vpn_endpoint_id" {
  description = "Client VPN endpoint ID."
  value       = module.vpn.endpoint_id
}

output "vpn_associated" {
  description = "Whether the Client VPN endpoint is currently associated with a subnet."
  value       = module.vpn.associated
}

output "gitea_admin_username" {
  description = "Gitea admin username."
  value       = module.gitea_server.admin_username
}

output "gitea_admin_password_ssm_name" {
  description = "SSM parameter name holding the Gitea admin password."
  value       = module.gitea_server.admin_password_ssm_name
}

output "gitea_admin_api_token_ssm_name" {
  description = "SSM parameter name where the Gitea admin API token is stored after first boot."
  value       = module.gitea_server.admin_api_token_ssm_name
}

output "gitea_runner_token_ssm_name" {
  description = "SSM parameter name holding the runner registration token."
  value       = module.gitea_server.runner_token_ssm_name
}

output "gitea_server_ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the Gitea server."
  value       = module.gitea_server.ssm_session_command
}

output "gitea_server_instance_id" {
  description = "Gitea EC2 instance ID. Used by lifecycle scripts for SSM commands."
  value       = module.gitea_server.instance_id
}

output "gitea_data_volume_id" {
  description = "Persistent Gitea data EBS volume ID. Save this before soft teardown and pass it back on spin-up."
  value       = module.gitea_server.data_volume_id
}

output "gitea_runner_ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the Gitea runner."
  value       = module.gitea_runner.ssm_session_command
}

output "gitea_config_bucket" {
  description = "S3 bucket holding the rendered docker-compose templates."
  value       = module.s3_config.bucket_name
}

output "gitea_backup_bucket" {
  description = "S3 bucket where the daily Gitea dump cron writes."
  value       = module.s3_backup.bucket_name
}
