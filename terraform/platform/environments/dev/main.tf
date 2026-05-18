data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "alexanderkachar-terraform-state"
    key    = "fully-private-argocd-on-eks/infra/dev/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  platform_manifests_repo_url = "https://${local.infra.gitea_hostname}/${var.gitea_org}/platform-manifests.git"
}

module "aws_lb_controller" {
  source = "../../modules/aws-lb-controller"

  cluster_name          = local.infra.cluster_name
  vpc_id                = local.infra.vpc_id
  region                = var.region
  ecr_registry_url      = local.infra.ecr_registry_url
  pod_identity_role_arn = local.infra.load_balancer_controller_role_arn
}

module "external_secrets" {
  source = "../../modules/external-secrets"

  cluster_name          = local.infra.cluster_name
  region                = var.region
  ecr_registry_url      = local.infra.ecr_registry_url
  pod_identity_role_arn = local.infra.external_secrets_role_arn
}

module "argocd" {
  source = "../../modules/argocd"

  cluster_name                    = local.infra.cluster_name
  region                          = var.region
  ecr_registry_url                = local.infra.ecr_registry_url
  argocd_target_group_arn         = local.infra.argocd_target_group_arn
  platform_manifests_repo_url     = local.platform_manifests_repo_url
  gitea_username                  = local.infra.gitea_admin_username
  platform_deploy_token_ssm_name  = var.platform_deploy_token_ssm_name
  application_controller_role_arn = local.infra.argocd_application_controller_role_arn
  image_updater_role_arn          = local.infra.argocd_image_updater_role_arn

  depends_on = [
    module.aws_lb_controller,
    module.external_secrets,
  ]
}
