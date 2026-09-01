output "application_url" {
  description = "Public application URL. Allow a few minutes after deployment for health checks."
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "product_table_name" {
  value = aws_dynamodb_table.products.name
}
