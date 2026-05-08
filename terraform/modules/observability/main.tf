locals {
  script = "${path.module}/push-observability-chart.sh"

  # Re-push whenever chart source files change. Hashing Chart.yaml covers
  # version bumps; hashing values.yaml and templates covers content changes.
  chart_hash = sha1(join("", [
    filesha1("${var.chart_dir}/Chart.yaml"),
    filesha1("${var.chart_dir}/values.yaml"),
  ]))
}

data "aws_region" "current" {}

# Extract the chart version so helm_release can reference the exact OCI tag.
data "external" "chart_version" {
  program = ["bash", "-c", "helm show chart '${var.chart_dir}' | awk -F': ' '$1==\"version\"{print \"{\\\"version\\\":\\\"\" $2 \"\\\"}\"}' "]
}

resource "null_resource" "push_chart" {
  triggers = {
    chart_hash = local.chart_hash
    repository = "${var.ecr_registry}/${var.ecr_repository}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash "${local.script}" \
        --chart-dir "${var.chart_dir}" \
        --repository "${var.ecr_repository}" \
        --region "${var.region}" \
        --registry "${var.ecr_registry}"
    EOT
  }
}

resource "helm_release" "observability" {
  name             = var.release_name
  repository       = "oci://${var.ecr_registry}"
  chart            = var.ecr_repository
  version          = data.external.chart_version.result["version"]
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  set {
    name  = "grafanaTargetGroupBinding.enabled"
    value = "true"
  }

  set {
    name  = "grafanaTargetGroupBinding.targetGroupArn"
    value = var.grafana_target_group_arn
  }

  set {
    name  = "grafanaTargetGroupBinding.targetType"
    value = "ip"
  }

  depends_on = [null_resource.push_chart]
}
