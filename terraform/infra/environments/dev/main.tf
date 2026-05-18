locals {
  cluster_name              = "${var.project_name}-${var.environment}-cluster"
  app_ecr_repository_name   = "${var.project_name}-${var.environment}-app"

  # Mirror repositories — one ECR repo per third-party image in scripts/images.yaml.
  # Names must match the `dest` field in that file.
  mirror_ecr_repository_names = [
    "argocd",
    "argocd-image-updater",
    "aws-load-balancer-controller",
    "dex",
    "external-secrets",
    "grafana",
    "k8s-sidecar",
    "kube-state-metrics",
    "kube-webhook-certgen",
    "loki",
    "nginx-unprivileged",
    "node-exporter",
    "prometheus",
    "prometheus-operator",
    "promtail",
    "redis",
  ]
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
  repository_names = concat(
    [local.app_ecr_repository_name],
    local.mirror_ecr_repository_names,
  )
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

module "s3_config" {
  source = "../../modules/s3-config"

  project_name = var.project_name
  environment  = var.environment
}

module "s3_backup" {
  source = "../../modules/s3-backup"

  project_name = var.project_name
  environment  = var.environment
}

module "gitea_server" {
  source = "../../modules/gitea-server"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  vpn_client_cidr   = module.vpn.client_cidr_block
  subnet_id         = module.vpc.services_subnet_ids[0]
  availability_zone = module.vpc.services_subnet_azs[0]

  gitea_hostname     = module.route53.gitea_hostname
  config_bucket_name = module.s3_config.bucket_name
  config_bucket_arn  = module.s3_config.bucket_arn
  backup_bucket_name = module.s3_backup.bucket_name
  backup_bucket_arn  = module.s3_backup.bucket_arn

  alb_target_group_arn = module.alb_internal.gitea_target_group_arn
}

module "gitea_runner" {
  source = "../../modules/gitea-runner"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
  subnet_id    = module.vpc.services_subnet_ids[1]

  gitea_instance_url    = "https://${module.route53.gitea_hostname}"
  config_bucket_name    = module.s3_config.bucket_name
  config_bucket_arn     = module.s3_config.bucket_arn
  runner_token_ssm_name = module.gitea_server.runner_token_ssm_name

  ecr_repository_arns       = values(module.ecr.repository_arns)
  cluster_name              = module.eks.cluster_name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
}
