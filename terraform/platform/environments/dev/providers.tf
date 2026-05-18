terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.70" }
    helm = { source = "hashicorp/helm", version = "~> 3.1" }
  }

  backend "s3" {
    bucket = "alexanderkachar-terraform-state"
    key    = "fully-private-argocd-on-eks/platform/dev/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes = {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", local.infra.cluster_name,
        "--region", var.region,
      ]
    }
  }
}
