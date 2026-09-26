variable "aws_region" {
  description = "AWS region for the low-cost demo. Pick a region where the chosen instance type and AZs are available."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short lowercase prefix used for every resource name."
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
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the single demo VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet."
  type        = string
  default     = "10.40.1.0/24"
}

variable "availability_zone" {
  description = "Optional AZ override. When null the first available AZ in the region is used."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "Graviton (ARM64) instance type for the demo host."
  type        = string
  default     = "t4g.small"
}

variable "root_volume_size_gb" {
  description = "Size of the encrypted gp3 root volume. 20 GB comfortably fits the OS, Docker, and demo images."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 16384
    error_message = "root_volume_size_gb must be between 8 and 16384."
  }
}

variable "root_volume_type" {
  description = "EBS volume type. gp3 is the cost-effective default."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2"], var.root_volume_type)
    error_message = "root_volume_type must be gp3 or gp2."
  }
}

variable "root_volume_iops" {
  description = "gp3 provisioned IOPS. The 3000 baseline is included in the gp3 price."
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "gp3 throughput in MiB/s. The 125 MiB/s baseline is included in the gp3 price."
  type        = number
  default     = 125
}

variable "cpu_credits" {
  type        = string
  default     = "standard"
  description = "T-family CPU credit mode. Standard is the cost-safe default."

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be standard or unlimited."
  }
}

variable "allowed_http_cidrs" {
  description = "CIDRs allowed to reach the instance on ports 80/443. Keep 0.0.0.0/0 for a public demo site."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "parameter_path_prefix" {
  description = "Parameter Store namespace the instance may read. Least privilege is limited to this prefix."
  type        = string
  default     = "/ecommerce/"

  validation {
    condition     = endswith(var.parameter_path_prefix, "/")
    error_message = "parameter_path_prefix must end with '/'."
  }
}

variable "install_docker" {
  description = "Whether user-data installs and enables Docker Engine plus the Compose plugin."
  type        = bool
  default     = true
}

variable "ssm_agent_enabled" {
  description = "Enable Session Manager access. Recommended: administration happens over SSM, never SSH."
  type        = bool
  default     = true
}

variable "create_budget" {
  description = "Optionally create an AWS Budgets cost budget with an email alert. Disabled by default because budgets are account-level."
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD used when create_budget is true."
  type        = string
  default     = "10"
}

variable "budget_email" {
  description = "Email address that receives budget alerts. Required only when create_budget is true."
  type        = string
  default     = ""
}
