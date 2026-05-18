locals {
  name_prefix = "${var.project_name}-${var.environment}"
  ssm_name    = "/${var.project_name}/gitea/backup-bucket"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket = "${local.name_prefix}-gitea-backups-${random_id.suffix.hex}"

  # Backups are precious — destroy is opt-in via teardown-hard, where
  # force_destroy is briefly flipped on by a separate var. Keep it off here
  # so an accidental `terraform destroy` cannot wipe historical dumps.
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-gitea-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "daily-dumps"
    status = "Enabled"

    filter {
      prefix = "daily/"
    }

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }
  }
}

resource "aws_ssm_parameter" "bucket_name" {
  name        = local.ssm_name
  description = "Gitea backup bucket name. Read by backup/restore scripts."
  type        = "String"
  value       = aws_s3_bucket.this.bucket
}
