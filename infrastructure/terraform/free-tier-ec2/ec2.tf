# Amazon Linux 2023 ARM64 (Graviton) resolved dynamically from the public SSM
# parameter so the AMI ID is never hard-coded and always tracks the latest
# patched AL2023 build for the selected region.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "demo" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.demo.id]
  iam_instance_profile   = aws_iam_instance_profile.demo.name

  # A public IPv4 address is required so nginx can serve traffic and the host
  # can reach GHCR/SSM/ACME without a NAT Gateway. No Elastic IP is created, so
  # the address changes on stop/start and no idle EIP charge accrues.
  associate_public_ip_address = true

  user_data                   = file("${path.module}/user-data.sh")
  user_data_replace_on_change = true

  # IMDSv2 is mandatory: session tokens are required, so SSRF-style credential
  # theft through the instance metadata service is not possible.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size_gb
    iops                  = var.root_volume_type == "gp3" ? var.root_volume_iops : null
    throughput            = var.root_volume_type == "gp3" ? var.root_volume_throughput : null
    encrypted             = true
    delete_on_termination = true
  }

  # AL2023 enables chrony by default; keeping it explicit documents that NTP is
  # available for TLS validity without opening additional ingress.
  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2"
    Role = "docker-compose-host"
  }

  lifecycle {
    precondition {
      condition     = !(var.create_budget && var.budget_email == "")
      error_message = "Set budget_email when create_budget = true."
    }
  }
}
