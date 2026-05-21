locals {
  service_account  = "external-secrets"
  image_repository = "${var.ecr_registry_url}/external-secrets"
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.service_account
  role_arn        = var.pod_identity_role_arn
}

resource "helm_release" "this" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = var.namespace
  create_namespace = true
  version          = var.chart_version
  wait             = true
  timeout          = 300
  upgrade_install  = true

  values = [
    yamlencode({
      image = {
        repository = local.image_repository
        tag        = var.image_tag
      }

      serviceAccount = {
        create = true
        name   = local.service_account
      }

      webhook = {
        image = {
          repository = local.image_repository
          tag        = var.image_tag
        }
      }

      certController = {
        image = {
          repository = local.image_repository
          tag        = var.image_tag
        }
      }
    }),
  ]

  depends_on = [aws_eks_pod_identity_association.this]
}

resource "helm_release" "cluster_secret_store" {
  name            = "external-secrets-cluster-store"
  chart           = "${path.module}/chart"
  namespace       = var.namespace
  wait            = true
  timeout         = 120
  upgrade_install = true

  values = [
    yamlencode({
      region = var.region
    }),
  ]

  depends_on = [helm_release.this]
}
