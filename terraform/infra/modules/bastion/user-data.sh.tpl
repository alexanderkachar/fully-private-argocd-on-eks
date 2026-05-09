#!/bin/bash
set -eux

dnf update -y
dnf install -y awscli git tar gzip unzip jq

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/

# helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x get_helm.sh && ./get_helm.sh

# terraform
TERRAFORM_VERSION="$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
curl -fsSL -o terraform.zip "https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip"
unzip -o terraform.zip -d /usr/local/bin/
rm terraform.zip

# argocd CLI (for the next stage)
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# kubeconfig
install -d -m 755 /etc/eks
aws eks update-kubeconfig \
  --name ${cluster_name} \
  --region ${region} \
  --kubeconfig /etc/eks/kubeconfig
chmod 644 /etc/eks/kubeconfig

install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.kube
ln -sf /etc/eks/kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

cat >/etc/profile.d/eks-kubeconfig.sh <<'EOF'
export KUBECONFIG="$${KUBECONFIG:-/etc/eks/kubeconfig}"
EOF

# clone repo so the platform terraform layer is available
REPO_DIR="/opt/repo"
git clone "${github_repo_url}" "$REPO_DIR"
chown -R ec2-user:ec2-user "$REPO_DIR"

# helper: run from an SSM session to apply the platform layer
cat >/usr/local/bin/deploy-platform <<'SCRIPT'
#!/bin/bash
set -euo pipefail
cd /opt/repo
git pull --ff-only
cd terraform/platform/environments/dev
terraform init -input=false
terraform apply -input=false -auto-approve
SCRIPT
chmod +x /usr/local/bin/deploy-platform

# helper: run from an SSM session to destroy the platform layer
cat >/usr/local/bin/destroy-platform <<'SCRIPT'
#!/bin/bash
set -euo pipefail
cd /opt/repo
git pull --ff-only
cd terraform/platform/environments/dev
terraform init -input=false
terraform destroy -input=false -auto-approve
SCRIPT
chmod +x /usr/local/bin/destroy-platform
