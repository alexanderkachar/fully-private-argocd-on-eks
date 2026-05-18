locals {
  cluster_name              = "${var.project_name}-${var.environment}-cluster"
  app_ecr_repository_name   = "${var.project_name}-${var.environment}-app"
  chart_ecr_repository_name = "express-app"
  pat_ssm_parameter_name    = "/${var.project_name}/github/pat"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
  route_table_ids = concat(
    module.vpc.private_route_table_ids,
    module.vpc.services_route_table_ids,
  )
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  repository_names = [
    local.app_ecr_repository_name,
    local.chart_ecr_repository_name,
  ]
}

module "route53" {
  source = "../../modules/route53"

  domain_name             = var.domain_name
  vpc_id                  = module.vpc.vpc_id
  app_subdomain           = var.app_subdomain
  grafana_subdomain       = var.grafana_subdomain
  argocd_subdomain        = var.argocd_subdomain
  gitea_subdomain         = var.gitea_subdomain
  certificate_domain_name = var.certificate_domain_name
}

module "eks" {
  source = "../../modules/eks"

  project_name                      = var.project_name
  environment                       = var.environment
  cluster_name                      = local.cluster_name
  cluster_version                   = var.cluster_version
  subnet_ids                        = module.vpc.private_subnet_ids
  cluster_role_arn                  = module.iam.cluster_role_arn
  node_role_arn                     = module.iam.node_role_arn
  ebs_csi_role_arn                  = module.iam.ebs_csi_role_arn
  load_balancer_controller_role_arn = module.iam.load_balancer_controller_role_arn
  admin_principal_arn               = var.admin_principal_arn
}

module "vpn" {
  source = "../../modules/vpn"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  association_subnet_id = module.vpc.public_subnet_ids[0]
  associated            = var.vpn_associated
  client_cidr_block     = var.vpn_client_cidr
}

module "alb_public" {
  source = "../../modules/alb-public"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  hosted_zone_id            = module.route53.public_hosted_zone_id
  app_hostname              = module.route53.app_hostname
  certificate_arn           = module.route53.certificate_arn
}

module "alb_internal" {
  source = "../../modules/alb-internal"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  vpc_cidr                  = module.vpc.vpc_cidr
  vpn_client_cidr           = module.vpn.client_cidr_block
  private_subnet_ids        = module.vpc.private_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  certificate_arn           = module.route53.certificate_arn
  hosted_zone_id            = module.route53.private_hosted_zone_id
  argocd_hostname           = module.route53.argocd_hostname
  grafana_hostname          = module.route53.grafana_hostname
  gitea_hostname            = module.route53.gitea_hostname
}

module "runner" {
  source = "../../modules/runner"

  project_name     = var.project_name
  environment      = var.environment
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr
  runner_subnet_id = module.vpc.services_subnet_ids[0]

  github_owner           = var.github_owner
  github_repo            = var.github_repo
  pat_ssm_parameter_name = local.pat_ssm_parameter_name

  ecr_repository_arns     = values(module.ecr.repository_arns)
  route53_hosted_zone_arn = module.route53.public_hosted_zone_arn

  cluster_name              = module.eks.cluster_name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
}
