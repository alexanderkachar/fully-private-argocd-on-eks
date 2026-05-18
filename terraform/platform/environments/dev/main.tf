data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "alexanderkachar-terraform-state"
    key    = "fully-private-argocd-on-eks/infra/dev/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.13.0"
  wait       = true
  timeout    = 300

  set {
    name  = "clusterName"
    value = local.infra.cluster_name
  }

  set {
    name  = "vpcId"
    value = local.infra.vpc_id
  }

  set {
    name  = "region"
    value = var.region
  }
}

module "observability" {
  source = "../../modules/observability"

  chart_dir                = "${path.module}/../../../../charts/observability"
  grafana_target_group_arn = local.infra.grafana_target_group_arn

  depends_on = [helm_release.aws_load_balancer_controller]
}

module "argocd" {
  source = "../../modules/argocd"

  argocd_target_group_arn = local.infra.argocd_target_group_arn
  app_target_group_arn    = local.infra.app_target_group_arn
  app_ecr_image_uri       = local.infra.app_ecr_image_uri
  github_owner            = var.github_owner
  github_repo             = var.github_repo
  pat_ssm_parameter_name  = var.pat_ssm_parameter_name
  region                  = var.region

  depends_on = [helm_release.aws_load_balancer_controller]
}
