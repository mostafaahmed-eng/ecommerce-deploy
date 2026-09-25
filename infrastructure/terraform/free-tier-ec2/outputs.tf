output "instance_id" {
  description = "EC2 instance ID. Pass this to the GitHub variable AWS_INSTANCE_ID so workflows can deploy with SSM Run Command."
  value       = aws_instance.demo.id
}

output "public_ip" {
  description = "Dynamic public IPv4 address. It changes on stop/start because no Elastic IP is allocated."
  value       = aws_instance.demo.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance."
  value       = aws_instance.demo.public_dns
}

output "application_http_url" {
  description = "Plain HTTP entry point for the demo storefront."
  value       = "http://${aws_instance.demo.public_dns}/"
}

output "vpc_id" {
  value = aws_vpc.demo.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_id" {
  value = aws_security_group.demo.id
}

output "iam_role_name" {
  value = aws_iam_role.demo.name
}

output "ami_id" {
  description = "Resolved Amazon Linux 2023 ARM64 AMI."
  value       = data.aws_ssm_parameter.al2023_arm64.value
}

output "parameter_namespace" {
  description = "Parameter Store prefix this instance is allowed to read."
  value       = var.parameter_path_prefix
}

output "ssm_instructions" {
  description = "How to administer the host without SSH."
  value       = <<-EOT
    Start an interactive shell (no SSH key, no open port 22):

      aws ssm start-session --target ${aws_instance.demo.id} --region ${var.aws_region}

    Run a one-off command:

      aws ssm send-command \
        --target "${aws_instance.demo.id}" \
        --document-name "AWS-RunShellScript" \
        --region ${var.aws_region} \
        --parameters 'commands=["docker ps"]'

    Useful pre-baked helpers on the host:

      ecommerce-health          # containers + release + local smoke checks
      ec-status / ec-logs       # compose shortcuts

    Deployment root: /opt/ecommerce
      .deployment/current       # active image SHA
      .deployment/previous      # last known good SHA (rollback target)
      data/                     # durable application state
      uploads/receipts/         # durable payment receipts
  EOT
}

output "teardown_instructions" {
  value = <<-EOT
    Destroy the demo infrastructure (never run this against production):

      cd infrastructure/terraform/free-tier-ec2
      terraform destroy
  EOT
}
