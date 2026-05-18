locals {
  name_prefix = "${var.project_name}-${var.environment}"

  subnets = {
    public_a   = { cidr = "10.0.0.0/24", az = var.azs[0], tier = "public" }
    public_b   = { cidr = "10.0.1.0/24", az = var.azs[1], tier = "public" }
    services_a = { cidr = "10.0.10.0/24", az = var.azs[0], tier = "services" }
    services_b = { cidr = "10.0.11.0/24", az = var.azs[1], tier = "services" }
    private_a  = { cidr = "10.0.20.0/24", az = var.azs[0], tier = "private" }
    private_b  = { cidr = "10.0.21.0/24", az = var.azs[1], tier = "private" }
  }
}

data "aws_region" "current" {}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(
    {
      Name = "${local.name_prefix}-${each.key}"
      Tier = each.value.tier
    },
    # EKS cluster discovery on all subnets ALB/cluster can use.
    contains(["public", "private"], each.value.tier) ? {
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb" = "1"
    } : {},
    each.value.tier == "private" ? {
      "kubernetes.io/role/internal-elb" = "1"
    } : {},
  )
}

# Single NAT Gateway in public AZ-a — used only by the services tier (Gitea
# bootstrap pulls and Gitea Actions resolving GitHub action repos until they
# are mirrored locally). Private (cluster) subnets have NO default route to
# the internet; they reach AWS APIs through VPC endpoints only.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public_a"].id

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# Route tables — one per tier.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table" "services" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${local.name_prefix}-rt-services" }
}

# Private route table has only the local route. Cluster nodes reach AWS
# APIs via the VPC endpoints attached in the vpc-endpoints module.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-rt-private" }
}

locals {
  route_table_by_tier = {
    public   = aws_route_table.public.id
    services = aws_route_table.services.id
    private  = aws_route_table.private.id
  }
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = local.route_table_by_tier[each.value.tier]
}
