locals {
  # Image overrides for the umbrella chart. Kept here (not in the chart's
  # values.yaml) so the chart remains registry-agnostic and the ECR prefix is
  # injected from infra outputs at apply time.
  image_overrides = {
    "kube-prometheus-stack" = {
      prometheus = {
        prometheusSpec = {
          image = {
            registry   = var.ecr_registry_url
            repository = "prometheus"
            tag        = "v3.11.3"
          }
        }
      }
      prometheusOperator = {
        image = {
          registry   = var.ecr_registry_url
          repository = "prometheus-operator"
          tag        = "v0.90.1"
        }
        prometheusConfigReloader = {
          image = {
            registry   = var.ecr_registry_url
            repository = "prometheus-operator"
            tag        = "v0.90.1"
          }
        }
        admissionWebhooks = {
          patch = {
            image = {
              registry   = var.ecr_registry_url
              repository = "kube-webhook-certgen"
              tag        = "1.8.2"
            }
          }
        }
      }
      grafana = {
        image = {
          registry   = var.ecr_registry_url
          repository = "grafana"
          tag        = "13.0.1"
        }
        sidecar = {
          image = {
            registry   = var.ecr_registry_url
            repository = "k8s-sidecar"
            tag        = "2.7.1"
          }
        }
      }
      kube-state-metrics = {
        image = {
          registry   = var.ecr_registry_url
          repository = "kube-state-metrics"
          tag        = "v2.18.0"
        }
      }
      prometheus-node-exporter = {
        image = {
          registry   = var.ecr_registry_url
          repository = "node-exporter"
          tag        = "v1.11.1"
        }
      }
    }

    loki = {
      loki = {
        image = {
          registry   = var.ecr_registry_url
          repository = "loki"
          tag        = "3.6.7"
        }
      }
      gateway = {
        image = {
          registry   = var.ecr_registry_url
          repository = "nginx-unprivileged"
          tag        = "1.29-alpine"
        }
      }
    }

    promtail = {
      image = {
        registry   = var.ecr_registry_url
        repository = "promtail"
        tag        = "3.5.1"
      }
    }
  }
}

# Observability platform release: kube-prometheus-stack + Loki + Promtail.
# Consumes the local umbrella chart at charts/observability — the chart
# bundles subchart .tgz files so the release does not need public internet.
resource "helm_release" "this" {
  name             = var.release_name
  chart            = "${path.module}/../../../../charts/observability"
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    yamlencode(merge(
      local.image_overrides,
      {
        grafanaTargetGroupBinding = {
          enabled        = true
          targetGroupArn = var.grafana_target_group_arn
          targetType     = "ip"
          serviceName    = "${var.release_name}-grafana"
          servicePort    = 80
        }
      }
    )),
  ]
}
