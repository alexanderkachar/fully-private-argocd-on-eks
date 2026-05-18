locals {
  image_updater_service_account = "argocd-image-updater"
}

resource "aws_eks_pod_identity_association" "application_controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "argocd-application-controller"
  role_arn        = var.application_controller_role_arn
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      global = {
        image = {
          repository = "${var.ecr_registry_url}/argocd"
          tag        = var.argocd_image_tag
        }
      }

      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          "admin.enabled" = true
        }
      }

      controller = {
        serviceAccount = {
          create = true
          name   = "argocd-application-controller"
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }

      dex = {
        image = {
          repository = "${var.ecr_registry_url}/dex"
          tag        = var.dex_image_tag
        }
      }

      redis = {
        image = {
          repository = "${var.ecr_registry_url}/redis"
          tag        = var.redis_image_tag
        }
      }
    }),
  ]

  depends_on = [aws_eks_pod_identity_association.application_controller]
}

resource "helm_release" "argocd_bootstrap" {
  name      = "argocd-bootstrap"
  chart     = "${path.module}/../../../../charts/argocd"
  namespace = var.namespace
  wait      = true
  timeout   = 120

  values = [
    yamlencode({
      targetGroupBinding = {
        targetGroupArn = var.argocd_target_group_arn
        targetType     = "ip"
        port           = 80
      }

      repoCredentials = {
        secretName        = "argocd-gitea-creds"
        repoURL           = var.platform_manifests_repo_url
        username          = var.gitea_username
        tokenSsmParameter = var.platform_deploy_token_ssm_name
      }

      rootApplication = {
        name           = "root"
        repoURL        = var.platform_manifests_repo_url
        targetRevision = "main"
        path           = "apps"
      }
    }),
  ]

  depends_on = [helm_release.argocd]
}

resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.image_updater_service_account
  role_arn        = var.image_updater_role_arn
}

resource "helm_release" "image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = var.image_updater_chart_version
  namespace  = var.namespace
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      image = {
        repository = "${var.ecr_registry_url}/argocd-image-updater"
        tag        = var.image_updater_image_tag
      }

      serviceAccount = {
        create = true
        name   = local.image_updater_service_account
      }

      config = {
        registries = [
          {
            name        = "ECR"
            api_url     = "https://${var.ecr_registry_url}"
            prefix      = var.ecr_registry_url
            ping        = true
            credentials = "ext:/scripts/ecr-login.sh"
            credsexpire = "10h"
          },
        ]
      }

      authScripts = {
        enabled = true
        scripts = {
          "ecr-login.sh" = "#!/bin/sh\naws ecr get-login-password --region ${var.region}"
        }
      }
    }),
  ]

  depends_on = [
    aws_eks_pod_identity_association.image_updater,
    helm_release.argocd_bootstrap,
  ]
}
