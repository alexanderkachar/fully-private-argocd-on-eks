locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-internal-alb-sg"
  description = "HTTPS to the internal admin ALB (ArgoCD/Grafana/Gitea) from inside the VPC and from VPN clients."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from inside the VPC."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "HTTPS from VPN clients."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    description = "Allow all egress."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-internal-alb-sg"
  }
}

# IP targets land on cluster pod ENIs (ArgoCD, Grafana) or directly on the
# Gitea EC2. For pod ENIs the cluster SG must accept ALB traffic on the
# pod port; for Gitea we manage the SG inside the gitea-server module.
resource "aws_security_group_rule" "alb_to_cluster_argocd" {
  type                     = "ingress"
  description              = "Internal ALB to ArgoCD pod targets."
  from_port                = var.argocd_target_port
  to_port                  = var.argocd_target_port
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "alb_to_cluster_grafana" {
  count = var.grafana_target_port == var.argocd_target_port ? 0 : 1

  type                     = "ingress"
  description              = "Internal ALB to Grafana pod targets."
  from_port                = var.grafana_target_port
  to_port                  = var.grafana_target_port
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.this.id
}

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-internal-alb"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.this.id]
  subnets            = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-internal-alb"
  }
}

# Default action returns 404 so the listener never resolves to a wrong
# backend if Host header doesn't match any rule.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

# ----- ArgoCD -----

resource "aws_lb_target_group" "argocd" {
  name        = "${local.name_prefix}-argocd-tg"
  port        = var.argocd_target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-399"
    path                = var.argocd_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name_prefix}-argocd-tg" }
}

resource "aws_lb_listener_rule" "argocd" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argocd.arn
  }

  condition {
    host_header {
      values = [var.argocd_hostname]
    }
  }
}

resource "aws_route53_record" "argocd" {
  zone_id         = var.hosted_zone_id
  name            = var.argocd_hostname
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

# ----- Grafana -----

resource "aws_lb_target_group" "grafana" {
  name        = "${local.name_prefix}-grafana-tg"
  port        = var.grafana_target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-399"
    path                = var.grafana_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name_prefix}-grafana-tg" }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = [var.grafana_hostname]
    }
  }
}

resource "aws_route53_record" "grafana" {
  zone_id         = var.hosted_zone_id
  name            = var.grafana_hostname
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

# ----- Gitea -----

resource "aws_lb_target_group" "gitea" {
  name        = "${local.name_prefix}-gitea-tg"
  port        = var.gitea_target_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-399"
    path                = var.gitea_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name_prefix}-gitea-tg" }
}

resource "aws_lb_listener_rule" "gitea" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitea.arn
  }

  condition {
    host_header {
      values = [var.gitea_hostname]
    }
  }
}

resource "aws_route53_record" "gitea" {
  zone_id         = var.hosted_zone_id
  name            = var.gitea_hostname
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}
