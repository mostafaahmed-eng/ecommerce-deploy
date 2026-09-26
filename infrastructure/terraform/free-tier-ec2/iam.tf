# Least-privilege instance role.
#  - AmazonSSMManagedInstanceCore : required for Session Manager / Run Command.
#  - ReadApplicationParameters   : read-only access to /ecommerce/* only.
# There is deliberately no PowerUserAccess and no AdministratorAccess.
#
# Exactly one wildcard exists (kms:Decrypt, below). It cannot be resource-scoped
# to /ecommerce/* because KMS keys are not addressable that way, so it is
# constrained by the kms:ViaService condition instead: the key may only be used
# through SSM in this region. Read access to SSM itself is separately scoped to
# parameter/ecommerce/*, so this role still cannot read other parameters.

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "demo" {
  name               = "${var.project_name}-${var.environment}-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2"
  }
}

# Managed policy that enables the SSM agent to register the instance and open
# shell sessions / run commands. Required for SSH-less administration.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.ssm_agent_enabled ? 1 : 0
  role       = aws_iam_role.demo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped-down read access to the application parameter namespace only.
data "aws_iam_policy_document" "application_parameters" {
  statement {
    sid       = "ReadApplicationParameters"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_path_prefix}*"]
  }

  # GetParameter with decryption requires kms:Decrypt on the key that guards
  # SecureString values. The default AWS-managed key is not resource-scoped, so
  # this statement is only meaningful when a customer-managed key is supplied.
  statement {
    sid       = "DecryptApplicationParameters"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "application_parameters" {
  name   = "ReadApplicationParameters"
  role   = aws_iam_role.demo.name
  policy = data.aws_iam_policy_document.application_parameters.json
}

data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "demo" {
  name = "${var.project_name}-${var.environment}-ec2"
  role = aws_iam_role.demo.name

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2"
  }
}

# Optional cost guard-rail. Disabled by default because AWS Budgets is an
# account-level feature and would collide if several people apply this module.
resource "aws_budgets_budget" "demo" {
  count = var.create_budget ? 1 : 0

  name              = "${var.project_name}-${var.environment}-monthly"
  budget_type       = "COST"
  limit_amount      = var.budget_limit_usd
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2000-01-01_00:00"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project_name)]
  }

  dynamic "notification" {
    for_each = var.budget_email == "" ? [] : [1]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 80
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }

  dynamic "notification" {
    for_each = var.budget_email == "" ? [] : [1]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
