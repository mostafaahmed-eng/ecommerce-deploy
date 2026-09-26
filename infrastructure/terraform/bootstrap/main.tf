# =============================================================================
# AWS bootstrap: GitHub Actions OIDC deployment roles (+ optional extras)
#
# DEFAULT BEHAVIOUR IS THE SECURE, FREE-TIER-ONLY PATH. With default variables
# this root creates ONLY:
#
#   - the account-level GitHub OIDC provider (and only if one does not exist)
#   - the free-tier GitHub Actions IAM role
#   - the free-tier least-privilege SSM policy
#
# and creates NONE of:
#
#   - PowerUserAccess          (needs var.enable_legacy_ecs_role = true)
#   - the legacy ECS role      (needs var.enable_legacy_ecs_role = true)
#   - the S3 state bucket      (needs var.create_state_bucket     = true)
#
# The free-tier EC2 module keeps local state by default, so no remote-state
# bucket is required for the live demo.
#
# -----------------------------------------------------------------------------
# A. legacy ECS role   -> aws_iam_role.legacy_ecs      [OPT-IN, default off]
#    Broad (PowerUserAccess) because `terraform apply` for the EKS/ECS stack
#    has to create VPCs, clusters, ALBs, ECR repos, IAM roles, etc.
#    Consumed ONLY by .github/workflows/ci-cd.yml through the Actions secret
#    AWS_LEGACY_ROLE_ARN, whose workflow jobs are manual-only
#    (workflow_dispatch from refs/heads/main + inputs.deploy_legacy_ecs).
#    This variable is unrelated to the live demo.
#
# B. free-tier role    -> aws_iam_role.free_tier        [ALWAYS CREATED]
#    Least privilege. .github/workflows/deploy-free-tier.yml only ever calls
#    `aws ssm send-command` (AWS-RunShellScript) and
#    `aws ssm get-command-invocation` against ONE EC2 instance. It therefore
#    gets exactly those two actions and nothing else - no PowerUserAccess,
#    no AdministratorAccess, no iam:*, no ec2:*, no s3:*, no ssm:*.
#    Consumed through the Actions secret AWS_FREE_TIER_ROLE_ARN.
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
# OPTIONAL S3 bucket for Terraform remote state (private, versioned, encrypted,
# locked down against public access).
#
# Disabled by default: the free-tier EC2 module keeps its state locally, so the
# live demo does not need a remote-state bucket at all. Enable with
# var.create_state_bucket = true.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  count         = var.create_state_bucket ? 1 : 0
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = { Project = var.project_name, ManagedBy = "TerraformBootstrap" }
}

resource "aws_s3_bucket_versioning" "state" {
  count  = var.create_state_bucket ? 1 : 0
  bucket = aws_s3_bucket.state[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  count  = var.create_state_bucket ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count                   = var.create_state_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.state[0].id
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
#
# OPT-IN: every resource below is gated on var.enable_legacy_ecs_role, which
# defaults to false. With defaults NOTHING here exists - no role, no
# PowerUserAccess attachment, no legacy IAM policy. Enable it only if you
# actually intend to run the legacy ECS profile; it is unrelated to the
# free-tier live demo.
# =============================================================================
resource "aws_iam_role" "legacy_ecs" {
  count = var.enable_legacy_ecs_role ? 1 : 0
  name  = "${var.project_name}-github-actions-legacy"
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
# repository where PowerUserAccess is granted, it is bound to the legacy
# profile (which can only be triggered by workflow_dispatch from refs/heads/main
# with inputs.deploy_legacy_ecs == true), and the attachment itself does not
# exist unless var.enable_legacy_ecs_role = true.
resource "aws_iam_role_policy_attachment" "legacy_power_user" {
  count      = var.enable_legacy_ecs_role ? 1 : 0
  role       = aws_iam_role.legacy_ecs[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "legacy_manage_project_roles" {
  count = var.enable_legacy_ecs_role ? 1 : 0
  name  = "ManageProjectRoles"
  role  = aws_iam_role.legacy_ecs[0].id
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
        # CONFIRMED against the AWS Systems Manager Service Authorization
        # Reference: GetCommandInvocation exposes no resource type, i.e. it
        # does not support resource-level permissions, so any policy that omits
        # Resource "*" simply denies it. It therefore cannot be narrowed to the
        # instance or to the document.
        # SendCommand, by contrast, DOES support resource-level permissions and
        # stays scoped to AWS-RunShellScript plus the single EC2 instance in the
        # statement above.
        # Residual risk: a caller holding a valid CommandId could read another
        # command's output. The role cannot create commands for anything but
        # the single instance above, so in practice the reachable blast radius
        # is the output of its own deploy commands.
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

variable "create_state_bucket" {
  type        = bool
  default     = false
  description = "Create the optional S3 Terraform remote-state bucket."
}

variable "enable_legacy_ecs_role" {
  type        = bool
  default     = false
  description = "Create the broad legacy ECS GitHub Actions role. Disabled by default."
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
    Populate this AFTER the free-tier EC2 instance exists - it is the same
    value as the instance_id output of infrastructure/terraform/free-tier-ec2
    and as the GitHub Actions variable AWS_INSTANCE_ID. Leave null to keep the
    role fail-closed (the SendCommand statement then only matches a placeholder
    that is not a real instance, so the role cannot target anything).
  EOT
  type        = string
  default     = null
  nullable    = true
}

# =============================================================================
# Outputs - one ARN per profile. There is deliberately no generic
# `github_actions_role_arn` output any more, so neither workflow can be wired
# to the wrong role by accident.
#
# Outputs for OPT-IN resources evaluate to null when the resource is disabled,
# so reading them never errors.
# =============================================================================
# null unless var.create_state_bucket = true
output "state_bucket_name" { value = try(aws_s3_bucket.state[0].id, null) }

output "github_oidc_provider_arn" { value = local.oidc_provider_arn }

# Secret AWS_LEGACY_ROLE_ARN for .github/workflows/ci-cd.yml
# null unless var.enable_legacy_ecs_role = true (the default)
output "legacy_role_arn" { value = try(aws_iam_role.legacy_ecs[0].arn, null) }

# Secret AWS_FREE_TIER_ROLE_ARN for .github/workflows/deploy-free-tier.yml
output "free_tier_role_arn" { value = aws_iam_role.free_tier.arn }
