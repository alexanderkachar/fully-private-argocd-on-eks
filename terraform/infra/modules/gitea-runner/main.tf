locals {
  name = "${var.project_name}-${var.environment}-gitea-runner"

  runner_compose = templatefile("${path.module}/../../../../docker-compose/runner/docker-compose.yml.tpl", {
    runner_version     = var.runner_version
    gitea_instance_url = var.gitea_instance_url
  })

  runner_config = templatefile("${path.module}/../../../../docker-compose/runner/config.yaml.tpl", {})
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ----- Security group -----

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "Gitea act_runner: no inbound, all egress (NAT + VPC endpoints)."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg" }
}

# Runner reaches the private EKS API on 443 during kubectl steps in
# workflows. The EKS cluster security group is exposed as the API ingress SG.
resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_runner" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Gitea act_runner to private EKS API."

  tags = { Name = "${local.name}-to-cluster-api" }
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

data "aws_iam_policy_document" "runner" {
  statement {
    sid       = "ECRGetAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "EKSDescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [var.cluster_arn]
  }

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
    sid = "ReadRunnerToken"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.runner_token_ssm_name}",
    ]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "gitea-runner-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name
}

# ----- S3 uploads: rendered runner compose + runner config -----

resource "aws_s3_object" "compose" {
  bucket  = var.config_bucket_name
  key     = "runner/docker-compose.yml"
  content = local.runner_compose
}

resource "aws_s3_object" "config" {
  bucket  = var.config_bucket_name
  key     = "runner/config.yaml"
  content = local.runner_config
}

# ----- EC2 -----

locals {
  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    region                = data.aws_region.current.name
    config_bucket         = var.config_bucket_name
    runner_token_ssm_name = var.runner_token_ssm_name
    gitea_instance_url    = var.gitea_instance_url
    runner_version        = var.runner_version
    runner_name           = local.name
  })
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
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

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = { Name = local.name }

  depends_on = [aws_s3_object.compose, aws_s3_object.config]
}

# ----- EKS access entry for kubectl from workflows -----

resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.runner]
}
