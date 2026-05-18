locals {
  name           = "${var.project_name}-${var.environment}-gitea"
  admin_username = "fpargo-admin"

  ssm_prefix             = "/${var.project_name}/gitea"
  admin_password_ssm     = "${local.ssm_prefix}/admin-password"
  admin_api_token_ssm    = "${local.ssm_prefix}/admin-api-token"
  runner_token_ssm       = "${local.ssm_prefix}/runner-registration-token"

  compose_rendered = templatefile("${path.module}/../../../../docker-compose/gitea/docker-compose.yml.tpl", {
    gitea_version = var.gitea_version
    gitea_domain  = var.gitea_hostname
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ----- Security group -----

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "Gitea EC2: HTTP 3000 from VPC + VPN, all egress."
  vpc_id      = var.vpc_id

  ingress {
    description = "Gitea HTTP from inside the VPC (internal ALB lives here)."
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Gitea HTTP from VPN clients (direct access during bootstrap)."
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    description = "Allow all egress (NAT for ghcr.io image pulls; AWS APIs via VPC endpoints + NAT)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg" }
}

# ----- IAM -----

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  statement {
    sid = "ReadConfigBucket"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.config_bucket_arn,
      "${var.config_bucket_arn}/*",
    ]
  }

  statement {
    sid = "WriteBackups"
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      var.backup_bucket_arn,
      "${var.backup_bucket_arn}/*",
    ]
  }

  statement {
    sid = "GiteaSSMReadWrite"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*",
    ]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "gitea-server-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name
}

# ----- SSM Parameter: admin password -----

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#%^*-_+="
}

resource "aws_ssm_parameter" "admin_password" {
  name        = local.admin_password_ssm
  description = "Gitea admin user password. Generated once by Terraform."
  type        = "SecureString"
  value       = random_password.admin.result

  lifecycle {
    ignore_changes = [value]
  }
}

# Admin API token and runner registration token are PUT by user_data the
# first time Gitea boots — Terraform doesn't manage their values, only
# downstream consumers (gitea-runner, bootstrap script) read them.

# ----- S3 upload: rendered docker-compose -----

resource "aws_s3_object" "compose" {
  bucket  = var.config_bucket_name
  key     = "gitea/docker-compose.yml"
  content = local.compose_rendered

  # Recreate the instance when compose content changes, so user_data picks
  # up the new file. (We hash into user_data below.)
}

# ----- EBS data volume -----

resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${local.name}-data" }
}

# ----- EC2 -----

locals {
  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    region                   = data.aws_region.current.name
    config_bucket            = var.config_bucket_name
    backup_bucket            = var.backup_bucket_name
    admin_username           = local.admin_username
    admin_password_ssm_name  = local.admin_password_ssm
    admin_token_ssm_name     = local.admin_api_token_ssm
    runner_token_ssm_name    = local.runner_token_ssm
    data_volume_id_short     = trimprefix(aws_ebs_volume.data.id, "vol-")
  })
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  availability_zone           = var.availability_zone
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  user_data = local.user_data
  # Re-render user_data (and thus replace the instance) when the rendered
  # compose changes or when the data volume changes.
  user_data_replace_on_change = true

  tags = { Name = local.name }

  depends_on = [aws_s3_object.compose]
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id

  # When the instance replaces, detach the volume first.
  stop_instance_before_detaching = true
}

# ----- ALB target group attachment (internal ALB → Gitea EC2) -----

resource "aws_lb_target_group_attachment" "gitea" {
  target_group_arn = var.alb_target_group_arn
  target_id        = aws_instance.this.id
  port             = 3000
}
