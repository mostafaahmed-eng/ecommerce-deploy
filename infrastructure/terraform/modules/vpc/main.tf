variable "environment" { type = string }
variable "vpc_cidr" { type = string }

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = { Name = "vpc-${var.environment}" }
}

resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.${count.index + 1}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? 'a' : 'b'}"
  map_public_ip_on_launch = true
  
  tags = { Name = "public-${var.environment}-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.${count.index + 10}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? 'a' : 'b'}"
  
  tags = { Name = "private-${var.environment}-${count.index + 1}" }
}

output "vpc_id" { value = aws_vpc.main.id }
output "public_subnets" { value = aws_subnet.public[*].id }
output "private_subnets" { value = aws_subnet.private[*].id }