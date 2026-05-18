resource "helm_release" "observability" {
  name             = var.release_name
  chart            = var.chart_dir
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    yamlencode({
      grafanaTargetGroupBinding = {
        enabled        = true
        targetGroupArn = var.grafana_target_group_arn
        targetType     = "ip"
      }
    })
  ]
}
