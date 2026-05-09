data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "github_pat" {
  name            = var.pat_ssm_parameter_name
  with_decryption = true
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

  # Run ArgoCD server in HTTP mode; TLS is terminated at the ALB.
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
}

resource "helm_release" "argocd_config" {
  name      = "argocd-config"
  chart     = "${path.module}/../../../../charts/argocd"
  namespace = var.namespace
  wait      = true
  timeout   = 120

  set {
    name  = "targetGroupBinding.targetGroupArn"
    value = var.argocd_target_group_arn
  }

  set {
    name  = "app.repoURL"
    value = "https://github.com/${var.github_owner}/${var.github_repo}.git"
  }

  set {
    name  = "app.githubOwner"
    value = var.github_owner
  }

  set {
    name  = "app.githubRepo"
    value = var.github_repo
  }

  set_sensitive {
    name  = "gitCreds.password"
    value = data.aws_ssm_parameter.github_pat.value
  }

  depends_on = [helm_release.argocd]
}

resource "helm_release" "image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = var.image_updater_chart_version
  namespace  = var.namespace
  wait       = true
  timeout    = 300

  set {
    name  = "config.registries[0].name"
    value = "ECR"
  }

  set {
    name  = "config.registries[0].api_url"
    value = "https://${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  }

  set {
    name  = "config.registries[0].prefix"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  }

  set {
    name  = "config.registries[0].ping"
    value = "true"
  }

  set {
    name  = "config.registries[0].credentials"
    value = "ext:/scripts/ecr-login.sh"
  }

  set {
    name  = "config.registries[0].credsexpire"
    value = "10h"
  }

  set {
    name  = "authScripts.enabled"
    value = "true"
  }

  # ECR credential helper script — fetches a fresh token before each poll cycle.
  set {
    name  = "authScripts.scripts.ecr-login\\.sh"
    value = "#!/bin/sh\naws ecr get-login-password --region ${var.region}"
  }

  depends_on = [helm_release.argocd]
}
