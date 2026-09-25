output "application_url" {
  description = "Public HTTPS application URL. Allow DNS and ACM validation to complete before use."
  value       = "https://${var.domain_name}"
}

output "receipt_bucket_name" {
  description = "Private S3 bucket used by the payment service for receipt images."
  value       = aws_s3_bucket.receipts.bucket
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
