output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
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

output "github_actions_variables" {
  description = "GitHub Actions repository variables expected by deployment workflows."
  value = {
    AWS_REGION                = var.region
    EKS_CLUSTER_NAME          = module.eks.cluster_name
    VPC_ID                    = module.vpc.vpc_id
    APP_ECR_REPOSITORY        = local.app_ecr_repository_name
    HELM_CHART_ECR_REPOSITORY = local.chart_ecr_repository_name
    APP_HOSTNAME              = module.route53.app_hostname
    APP_TARGET_GROUP_ARN      = module.alb_public.target_group_arn
    GRAFANA_HOSTNAME          = module.route53.grafana_hostname
  }
}

output "runner_pat_put_command" {
  description = "Copy-paste command to seed the GitHub PAT into SSM for runner registration. Replace ghp_xxx with your actual token."
  value       = module.runner.runner_pat_put_command
}

output "runner_ssm_session_command" {
  description = "Copy-paste command to start an SSM session into the GitHub Actions runner for debugging."
  value       = module.runner.ssm_session_command
}
