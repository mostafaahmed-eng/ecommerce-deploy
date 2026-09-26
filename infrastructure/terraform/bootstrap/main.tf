# =============================================================================
# AWS bootstrap: Terraform state bucket + GitHub Actions OIDC deployment roles
#
# TWO SEPARATE ROLES ARE CREATED ON PURPOSE. They must never be shared.
#
#   A. legacy ECS role   -> aws_iam_role.legacy_ecs
#      Broad (PowerUserAccess) because `terraform apply` for the EKS/ECS stack
#      has to create VPCs, clusters, ALBs, ECR repos, IAM roles, etc.
#      Consumed ONLY by .github/workflows/ci-cd.yml through the Actions secret
#      AWS_LEGACY_ROLE_ARN, whose workflow jobs are manual-only
#      (workflow_dispatch from refs/heads/main + inputs.deploy_legacy_ecs).
#
#   B. free-tier role    -> aws_iam_role.free_tier
#      Least privilege. .github/workflows/deploy-free-tier.yml only ever calls
#      `aws ssm send-command` (AWS-RunShellScript) and
#      `aws ssm get-command-invocation` against ONE EC2 instance. It therefore
#      gets exactly those two actions and nothing else - no PowerUserAccess,
#      no AdministratorAccess, no iam:*, no ec2:*, no s3:*, no ssm:*.
#      Consumed through the Actions secret AWS_FREE_TIER_ROLE_ARN.
#
# THIS FILE IS NOT TO BE APPLIED YET. It is design-only until the AWS phase is
# explicitly opened.
# =============================================================================

terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" { region = var.aws_region }

data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}")

  account_id = data.aws_caller_identity.current.account_id

  # Shared trust conditions for BOTH roles: this exact repository, this exact
  # branch, and the GitHub OIDC audience. A pull_request run never matches
  # `ref:refs/heads/main`, so PR code cannot assume either role.
  github_trust_conditions = {
    StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
    }
    StringLike = {
      "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.deploy_branch}"
    }
  }

  # The token.actions.githubusercontent.com OIDC provider is ACCOUNT level and
  # normally exists only once. `try` picks up the managed resource when we are
  # creating it, otherwise the ARN of a provider that already exists in the
  # account (var.github_oidc_provider_arn).
  oidc_provider_arn = try(aws_iam_openid_connect_provider.github[0].arn, var.github_oidc_provider_arn)

  # Fail closed: with var.free_tier_instance_id left null the SendCommand
  # statement can only ever match this placeholder, which is not a real
  # instance id, so the role cannot target any instance until it is set.
  free_tier_instance_arn = var.free_tier_instance_id == null ? (
    "arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/UNSET-set-var.free_tier_instance_id"
    ) : (
    "arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/${var.free_tier_instance_id}"
  )

  free_tier_ssm_document_arn = "arn:aws:ssm:${var.aws_region}:${local.account_id}:document/AWS-RunShellScript"
}

# -----------------------------------------------------------------------------
# S3 bucket for Terraform remote state (private, versioned, encrypted, locked
# down against public access).
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = { Project = var.project_name, ManagedBy = "TerraformBootstrap" }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Account-level GitHub OIDC provider.
#
# There is normally only ONE token.actions.githubusercontent.com provider per
# AWS account, shared by every repository that uses GitHub Actions OIDC.
# Creating a second one fails with EntityAlreadyExists, so both cases are
# supported:
#
#   CASE 1 - no provider exists yet (default)
#       leave var.github_oidc_provider_arn null and Terraform creates it.
#
#   CASE 2 - a provider already exists
#       EITHER set it as an external reference so Terraform does not manage it:
#           github_oidc_provider_arn = "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
#       OR import it into this configuration so Terraform adopts it:
#           terraform import 'aws_iam_openid_connect_provider.github[0]' \
#             arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
#
# Only one of those two approaches may be used at a time.
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.github_oidc_provider_arn == null ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = { Project = var.project_name, ManagedBy = "TerraformBootstrap" }
}

# =============================================================================
# A. LEGACY ECS DEPLOYMENT ROLE - broad, manual-only, never used by free-tier
# =============================================================================
resource "aws_iam_role" "legacy_ecs" {
  name = "${var.project_name}-github-actions-legacy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = local.github_trust_conditions
    }]
  })
  tags = { Project = var.project_name, ManagedBy = "TerraformBootstrap", Profile = "legacy-ecs" }
}

# Kept for portfolio/reference purposes. This is the ONLY place in the whole
# repository where PowerUserAccess is granted, and it is bound to the legacy
# profile which can only be triggered by workflow_dispatch from refs/heads/main
# with inputs.deploy_legacy_ecs == true.
resource "aws_iam_role_policy_attachment" "legacy_power_user" {
  role       = aws_iam_role.legacy_ecs.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "legacy_manage_project_roles" {
  name = "ManageProjectRoles"
  role = aws_iam_role.legacy_ecs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateAssumeRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy", "iam:GetRolePolicy",
          "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags",
          "iam:UpdateRoleDescription", "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project_name}-*"
      }
    ]
  })
}

# =============================================================================
# B. FREE-TIER EC2 DEPLOYMENT ROLE - least privilege
#
# Derived strictly from what .github/workflows/deploy-free-tier.yml executes.
# The complete AWS API surface of that workflow is:
#
#   sts:AssumeRoleWithWebIdentity   <- the trust policy below, not an
#                                       identity permission, and it is already
#                                       restricted to repo + branch + audience
#   ssm:SendCommand                 <- aws ssm send-command
#                                         --document-name AWS-RunShellScript
#                                         --instance-id   <AWS_INSTANCE_ID>
#   ssm:GetCommandInvocation         <- aws ssm get-command-invocation (poll)
#
# Nothing else. The GHCR image push uses GITHUB_TOKEN and touches no AWS API.
# =============================================================================
resource "aws_iam_role" "free_tier" {
  name = "${var.project_name}-github-actions-free-tier"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = local.github_trust_conditions
    }]
  })
  tags = { Project = var.project_name, ManagedBy = "TerraformBootstrap", Profile = "free-tier" }
}

resource "aws_iam_policy" "free_tier_ssm_deploy" {
  name        = "${var.project_name}-free-tier-ssm-deploy"
  description = "Least-privilege permissions for the free-tier GitHub deployment workflow."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SendCommand is evaluated against BOTH resources involved in the call
        # (the Systems Manager document and the target instance), so both ARNs
        # must be listed for the call to be allowed. Listing them together is
        # what scopes the role down to AWS-RunShellScript on one instance.
        Sid    = "SendRunShellScriptToOneInstance"
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          local.free_tier_ssm_document_arn,
          local.free_tier_instance_arn,
        ]
      },
      {
        # RESOURCE "*" IS REQUIRED HERE AND IS NOT AN OVER-GRANT.
        # Per the AWS Service Authorization Reference for Systems Manager,
        # GetCommandInvocation does not expose a resource type, i.e. it does
        # not support resource-level permissions, so any policy that omits
        # Resource "*" simply denies it. It therefore cannot be narrowed to
        # the instance or the document.
        # Residual risk: a caller holding a valid CommandId could read another
        # command's output. The role cannot create commands for anything but
        # the single instance above, so in practice the reachable blast radius
        # is the output of its own deploy commands.
        # CONFIRM against the AWS Service Authorization Reference at apply time
        # - this document could not be reached from the build environment.
        Sid      = "ReadDeployCommandInvocation"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "free_tier_ssm" {
  role       = aws_iam_role.free_tier.name
  policy_arn = aws_iam_policy.free_tier_ssm_deploy.arn
}

# =============================================================================
# Variables
# =============================================================================
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "ecommerce-demo"
}

variable "github_repository" {
  description = "GitHub repository in owner/name format."
  type        = string
  default     = "mostafaahmed-eng/ecommerce-deploy"
}

variable "deploy_branch" {
  type    = string
  default = "main"
}

variable "state_bucket_name" {
  description = "Optional globally unique bucket name. The account ID is appended when null."
  type        = string
  default     = null
  nullable    = true
}

variable "github_oidc_provider_arn" {
  description = <<-EOT
    ARN of a token.actions.githubusercontent.com OIDC provider that ALREADY
    exists in this AWS account. When set, Terraform references it and does not
    create one. Leave null to let Terraform create the provider (then import it
    instead, if it already exists - see the comment above the resource).
  EOT
  type        = string
  default     = null
  nullable    = true
}

variable "free_tier_instance_id" {
  description = <<-EOT
    EC2 instance ID that aws_iam_role.free_tier may run AWS-RunShellScript on.
    Leave null to keep the role fail-closed (the SendCommand statement then
    only matches a placeholder that is not a real instance). Set it to the
    instance created by infrastructure/terraform/free-tier-ec2, which is also
    the value of the GitHub Actions variable AWS_INSTANCE_ID.
  EOT
  type        = string
  default     = null
  nullable    = true
}

# =============================================================================
# Outputs - one ARN per profile. There is deliberately no generic
# `github_actions_role_arn` output any more, so neither workflow can be wired
# to the wrong role by accident.
# =============================================================================
output "state_bucket_name" { value = aws_s3_bucket.state.id }

output "github_oidc_provider_arn" { value = local.oidc_provider_arn }

# Secret AWS_LEGACY_ROLE_ARN for .github/workflows/ci-cd.yml
output "legacy_role_arn" { value = aws_iam_role.legacy_ecs.arn }

# Secret AWS_FREE_TIER_ROLE_ARN for .github/workflows/deploy-free-tier.yml
output "free_tier_role_arn" { value = aws_iam_role.free_tier.arn }
