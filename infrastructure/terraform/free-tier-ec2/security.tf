# Single security group. Only the reverse proxy ports are reachable from the
# internet; application containers publish no host ports at all, and SSH (22)
# is intentionally absent - administration uses Session Manager / Run Command.

resource "aws_security_group" "demo" {
  name        = "${var.project_name}-${var.environment}-ec2"
  description = "HTTP/HTTPS only. SSH is managed through AWS Systems Manager Session Manager."
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "HTTP - public storefront"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  ingress {
    description = "HTTPS - public storefront once a certificate is issued"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  # Egress is open so the host can reach Docker Hub / GHCR, the SSM endpoints,
  # AWS APIs, the YUM repositories and Let's Encrypt without a NAT Gateway.
  egress {
    description = "Outbound package, image, SSM and ACME downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2"
  }
}
