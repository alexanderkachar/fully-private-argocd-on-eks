output "cluster_role_arn" {
  description = "IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM role attached to managed node group EC2 instances."
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  description = "Pod Identity role for the EBS CSI controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "load_balancer_controller_role_arn" {
  description = "Pod Identity role for AWS Load Balancer Controller."
  value       = aws_iam_role.load_balancer_controller.arn
}

output "external_secrets_role_arn" {
  description = "Pod Identity role for External Secrets Operator."
  value       = aws_iam_role.external_secrets.arn
}

output "argocd_application_controller_role_arn" {
  description = "Pod Identity role for the ArgoCD application controller."
  value       = aws_iam_role.argocd_application_controller.arn
}

output "argocd_image_updater_role_arn" {
  description = "Pod Identity role for ArgoCD Image Updater."
  value       = aws_iam_role.argocd_image_updater.arn
}
