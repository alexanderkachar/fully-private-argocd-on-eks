locals {
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.service_account
  role_arn        = var.pod_identity_role_arn
}

resource "helm_release" "this" {
  name            = "aws-load-balancer-controller"
  repository      = "https://aws.github.io/eks-charts"
  chart           = "aws-load-balancer-controller"
  namespace       = local.namespace
  version         = var.chart_version
  wait            = true
  timeout         = 300
  upgrade_install = true

  values = [
    yamlencode({
      clusterName = var.cluster_name
      vpcId       = var.vpc_id
      region      = var.region

      image = {
        repository = "${var.ecr_registry_url}/aws-load-balancer-controller"
        tag        = var.image_tag
      }

      serviceAccount = {
        create = true
        name   = local.service_account
      }
    }),
  ]

  depends_on = [aws_eks_pod_identity_association.this]
}
