output "bucket_name" {
  description = "Config bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Config bucket ARN."
  value       = aws_s3_bucket.this.arn
}
