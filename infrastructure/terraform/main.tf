terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  
  backend "s3" {
    bucket = "ecommerce-terraform-state"
    key    = "infrastructure/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" { default = "us-east-1" }
variable "environment" { default = "production" }

module "vpc" {
  source = "./modules/vpc"
  environment = var.environment
  vpc_cidr = "10.0.0.0/16"
}

module "eks" {
  source = "./modules/eks"
  cluster_name = "ecommerce-${var.environment}"
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}

output "eks_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id" { value = module.vpc.vpc_id }