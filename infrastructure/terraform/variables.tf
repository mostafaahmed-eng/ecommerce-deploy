variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short lowercase name used as an AWS resource prefix."
  type        = string
  default     = "ecommerce-demo"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "production"
}

variable "image_tag" {
  description = "Immutable image tag deployed for every service. GitHub Actions supplies the commit SHA."
  type        = string
  default     = ""
  validation {
    condition     = var.image_tag == "" || can(regex("^[0-9a-f]{7,64}$", var.image_tag))
    error_message = "image_tag must be a Git commit SHA; latest is not permitted for deployments."
  }
}

variable "domain_name" {
  description = "Public DNS name for the HTTPS storefront, for example store.example.com."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 public hosted-zone ID that is authoritative for domain_name."
  type        = string
}

variable "payment_secrets_arn" {
  description = "ARN of an existing Secrets Manager JSON secret containing the payment and admin runtime values."
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "allowed_http_cidrs" {
  description = "CIDRs allowed to reach the public ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "task_cpu" {
  description = "Fargate task CPU units for the multi-container demo."
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 2048
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "min_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type    = number
  default = 2
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "allow_repository_force_delete" {
  description = "Allows terraform destroy to delete non-empty demo ECR repositories."
  type        = bool
  default     = false
}

variable "enable_database_point_in_time_recovery" {
  description = "Enable continuous DynamoDB backups. Recommended outside short-lived demos."
  type        = bool
  default     = true
}

variable "enable_database_deletion_protection" {
  description = "Protect the product table from accidental deletion. Enable for long-lived environments."
  type        = bool
  default     = false
}
