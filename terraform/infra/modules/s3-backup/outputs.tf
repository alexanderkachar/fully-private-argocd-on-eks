output "bucket_name" {
  description = "Gitea backups bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Gitea backups bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "ssm_parameter_name" {
  description = "SSM Parameter holding the backup bucket name (used by backup/restore scripts)."
  value       = aws_ssm_parameter.bucket_name.name
}
