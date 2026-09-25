# Deliberately minimal networking: one VPC, one public subnet, one Internet
# Gateway. There is intentionally NO NAT Gateway, which is one of the most
# common sources of unexpected AWS cost (~$0.045/hour + data processing).

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zone = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

resource "aws_vpc" "demo" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
    # Type=public is consumed by the aws-load-balancer-controller style tooling
    # and makes the intent obvious to anyone reading the console.
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
