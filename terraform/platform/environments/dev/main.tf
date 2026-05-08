data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "alexanderkachar-terraform-state"
    key    = "eks-portfolio-project-charlie/infra/dev/terraform.tfstate"
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
