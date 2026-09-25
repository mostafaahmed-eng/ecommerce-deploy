# Low-cost AWS live demo — cost model, caveats and guard rails

This document covers the **second deployment profile**: one EC2 `t4g.small`
running Docker Compose behind Nginx. The original ECS/Fargate profile is
unchanged and documented in the root [`README.md`](../README.md).

> [!IMPORTANT]
> **T4g free trial.** At the time this deployment profile was prepared, AWS
> provides a T4g free trial covering up to 750 hours/month of `t4g.small` usage
> through **December 31, 2026**. Other resources, excess CPU credits, network
> usage, storage, public IPv4 usage outside applicable allowances, and usage
> after the trial may incur charges. Regular On-Demand billing starts
> **January 1, 2027**. Eligibility and AWS terms can change — confirm the
> current offer before you rely on it.

> [!CAUTION]
> **Nothing here guarantees a $0 bill.** The T4g free trial covers *compute on
> one instance family*; it does not cover every line item this profile creates,
> and it ends. This document tells you exactly what gets created, what it costs
> **during the trial**, what it costs **after the trial**, what is deliberately
> *not* created, and how to put a hard spending alarm in front of it. Read the
> **Pre-apply checklist** before running `terraform apply`.

---

## 1. Resources this profile creates

Everything lives in `infrastructure/terraform/free-tier-ec2/`.

| Resource | Count | Purpose | Approximate cost* |
| --- | --- | --- | --- |
| `aws_instance` `t4g.small` (Graviton2, 2 vCPU / 2 GiB) | 1 | Runs the whole stack | **$0 during the T4g free trial** (≤ 750 hrs/month through Dec 31 2026) → ≈ **$12/month** On-Demand from Jan 1, 2027 |
| `aws_ebs_volume` root, **gp3 20 GB**, encrypted | 1 | OS + Docker images + app data | ≈ $0.08/GB-month → ≈ **$1.60/month** |
| `aws_vpc` | 1 | Isolated network | **$0** |
| `aws_subnet` (single **public** subnet) | 1 | Public ingress | **$0** |
| `aws_internet_gateway` | 1 | Outbound/inbound internet | **$0** |
| `aws_route_table` + associations | 1 set | Routes to the IGW | **$0** |
| `aws_security_group` | 1 | Ingress **80/443 only**, no port 22 | **$0** |
| `aws_iam_role` + instance profile | 1 | `AmazonSSMManagedInstanceCore` + read-only `/ecommerce/*` | **$0** |
| `aws_ssm_document` parameter (AMI lookup) | 1 | Resolves the current AL2023 ARM64 AMI | **$0** |
| `aws_budgets_budget` + SNS topic/subscriptions | 0 by default | Optional spending alarm | **$0** unless `create_budget = true` |
| Public IPv4 address (auto-assigned) | 1 | Reachable over HTTP | Charged by AWS as of 2024 (**≈ $0.005/hr ≈ $3.65/month**) — see *Public IPv4 charge* below |

\* Prices are **estimates for `us-east-1` at the time of writing**. Always
confirm against the [AWS Pricing Calculator](https://calculator.aws/) and
`aws pricing get-products` before you rely on a number.

### 1a. Current situation — during the T4g free trial

At the time this deployment profile was prepared, AWS provides a T4g free trial
covering up to 750 hours/month of `t4g.small` usage through **December 31,
2026**. That is 744 hours in a 31-day month, so a `t4g.small` running 24/7 for a
whole month fits inside the allowance — with about 6 hours to spare.

```text
EC2 t4g.small (≤ 750 hrs/mo)   $0      during the free trial, through Dec 31 2026
                               ----
trial-period compute subtotal  $0
```

**This is still not a $0 total.** Everything *except* the trial-covered compute
is billed normally, and only where allowances apply:

```text
gp3 20 GB                      ≈  $1.60 / month   (see EBS allowances)
Public IPv4 (auto-assigned)    ≈  $3.65 / month   (see applicable allowances)
                               -----------------
everything other than trial-covered compute ≈ $5.25 / month
```

Charges that can appear **on top of** the trial:

- **CPU credits.** `t4g` instances accumulate and spend **surplus CPU credits**.
  Sustained CPU usage above the baseline can create charges, and credits
  purchased/expired outside the trial are billable.
- **Network / data transfer** beyond the free-tier allowances.
- **Storage** (EBS, snapshots, any future S3) beyond its own allowances.
- **Public IPv4 usage** outside applicable allowances.
- **Anything used after the trial ends.**

Stop the instance when you are not demoing and the compute *and* the public
IPv4 charges both stop; only the EBS volume keeps billing.

### 1b. Expected On-Demand cost — from January 1, 2027

Regular On-Demand billing starts **January 1, 2027**. With no trial and no
allowances applied, 24/7 in `us-east-1` looks like:

```text
EC2 t4g.small          ≈ $12.00 / month     ≈ $0.0164/hr
gp3 20 GB              ≈  $1.60 / month
Public IPv4 (auto)     ≈  $3.65 / month
                        -----------------
                        ≈ $17.25 / month
```

This ≈ **$17.25/month** figure is the **post-trial, 2027 On-Demand** number. It
is **not** the current expected bill while the T4g free trial applies.

Stop the instance when you are not demoing and the EC2 + IPv4 charges drop to
just the **EBS volume** (≈ $1.60/month), because a stopped instance does not
bill for compute or the public IPv4 address.

---

## 2. Free-tier caveats (read this before assuming it is free)

1. **There is no "$0 guaranteed" outcome.** The T4g free trial is an AWS
   offer with terms, not a property of the architecture. As stated at the time
   this profile was prepared: **`t4g.small`, up to 750 aggregate instance-hours
   per month, available to new and existing AWS customers, through
   December 31, 2026**, with regular On-Demand billing starting
   **January 1, 2027**. Whether *your* account qualifies, and whether the terms
   still stand, depends on:
   - your account's eligibility for the offer (AWS may change eligibility or
     terms at any time),
   - the aggregate hours consumed across all `t4g` instances in the account —
     750 hours/month is a **shared** allowance, and a 31-day month has 744
     hours, so 24/7 plus any second `t4g` instance can exceed it,
   - the region you deploy into,
   - the date: after December 31, 2026 the trial no longer applies.
2. **`t4g.small` is chosen for cost-per-performance, and it is the instance
   family the trial actually covers.** It is the cheapest instance that
   comfortably runs seven Node services plus Nginx, Prometheus and Grafana, and
   it sits inside the T4g free trial window. If you need more than 750
   aggregate hours — or you are running past the trial window — change
   `instance_type` in `terraform.tfvars.example`, or simply stop the instance
   when you are not demoing (stopping stops both compute and public IPv4
   billing; the EBS volume keeps billing).
3. **The trial covers compute only.** Free-tier allowances and the T4g trial do
   not cover data transfer, public IPv4 addresses outside applicable
   allowances, ECR storage, CloudWatch Logs ingestion or Route 53 hosted zones
   beyond their own allowances, and **surplus CPU credits** on `t4g` are a
   separate, billable item.
4. **Prices change.** gp3, EBS snapshots, public IPv4 and data transfer have
   all been repriced in recent years, and AWS free-tier/trial terms change too.
   Treat every figure above as an estimate and re-confirm the offer.
5. **The trial ends.** On-Demand billing resumes January 1, 2027 — see §1b for
   the post-trial figure.
6. **A forgotten instance is the classic surprise bill.** That is what the
   budget alarm in §4 is for. Enable it on the very first apply.

---

## 3. Cost traps this design deliberately avoids

| Cost trap | Typical 24/7 cost | Why it is avoided here |
| --- | --- | --- |
| NAT Gateway (per hour + per GB) | ≈ $32+/month | Single **public** subnet; instances reach the internet through the IGW. Private subnets were not needed. |
| Application Load Balancer | ≈ $16+/month + LCU | Nginx in a container on the instance terminates HTTP. |
| ECS Fargate (vCPU + memory) | Scales with every task | Docker Compose on one VM; no orchestrator fee. |
| EKS control plane | ≈ $73/month | Kubernetes profile is local/optional only. |
| RDS instance | ≈ $12+/month + storage + backups | Persistence is a JSON file on the EBS volume (§8 of `DEPLOYMENT_SUMMARY.md`). |
| Secrets Manager | ≈ $0.40/secret/month + API calls | Secrets live in **SSM Parameter Store Standard**, which is free for standard parameters. |
| Route 53 hosted zone + alias | ≈ $0.50/month | HTTP works with the bare instance IP/DNS name. DNS is only needed for stage-two HTTPS. |
| AWS WAF | ≈ $5+/month + rules | Not required for a portfolio demo. |
| Elastic IP (idle) | ≈ $3.65/month when unused | No EIP is allocated; the instance uses its auto-assigned address. A stopped instance therefore bills nothing for the address. |
| CloudWatch Logs (ingestion) | ≈ $0.50/GB | Containers log to the local `json-file` driver with rotation (`10m × 3` files per container). |
| ECR storage for 7 multi-arch images | ≈ $0.10/GB-month | Images go to **GitHub Container Registry**, not ECR. |
| AWS CodeBuild / CodePipeline minutes | metered | CI runs on GitHub Actions. |

---

## 4. Pre-apply checklist

Run through this **before** every `terraform apply`.

- [ ] `aws sts get-caller-identity` shows the account you intend.
- [ ] `cd infrastructure/terraform/free-tier-ec2 && terraform init -backend=false`
      has been run (this profile keeps state local by default).
- [ ] `terraform fmt -check -recursive` is clean.
- [ ] `terraform validate` succeeds.
- [ ] You have read `terraform plan` **in full** and every resource is one you
      recognise.
- [ ] `var.project_name` and `var.environment` are the values you expect —
      they appear in resource names and tags.
- [ ] `instance_type` is the instance you are willing to pay for (§1).
- [ ] `root_volume_size_gb` is the disk you are willing to pay for.
- [ ] `allowed_http_cidrs` is `0.0.0.0/0` **only** if this is meant to be
      publicly reachable, otherwise narrow it.
- [ ] `create_budget` is `true` and `budget_email` is set — **recommended on
      the very first apply** so you are alerted from day one.
- [ ] `ssm_agent_enabled` is `true` (you have no SSH, so SSM is your only
      access path).
- [ ] No `.tfstate`, `.tfvars` (non-example), `.tfplan` or `*.pem` file will be
      committed: `git status --porcelain` shows none of them.
- [ ] You know how to tear it down: `terraform destroy` (§7).

> [!IMPORTANT]
> Never run `terraform apply` against a saved plan you have not read, and never
> run `terraform destroy` from a shell whose AWS account you have not just
> verified.

---

## 5. Budget and spending alerts

### 5a. CLI (fastest, works without touching Terraform)

```bash
# One-time SNS topic + email confirmation subscription
aws sns create-topic --name ecommerce-demo-budget-alerts --query TopicArn --output text
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint you@example.com
# ==> confirm the subscription from your inbox before alerts are delivered

aws budgets create-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget '{
    "BudgetName": "ecommerce-demo-monthly",
    "BudgetLimit": { "Amount": "10", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [{ "SubscriptionType": "SNS", "Address": "'"${TOPIC_ARN}"'" }]
  }]'
```

### 5b. Optional Terraform (disabled by default)

```bash
cd infrastructure/terraform/free-tier-ec2
terraform plan \
  -var='create_budget=true' \
  -var='budget_email=you@example.com' \
  -var='budget_limit_usd=10'
```

`create_budget` defaults to **`false`** so a plain `terraform plan` creates no
account-level resources. `aws_budgets_budget` and the SNS topic/subscriptions
only exist when it is switched on.

### 5c. Quick "what am I spending" checks

```bash
# Cost and Usage Report for the current month so far
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE

# Anything currently running that you have forgotten about
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,LaunchTime,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## 6. Parameter Store layout (`/ecommerce/*`)

Secrets are never in Git, never in `tfvars`, and never in GitHub variables.
`scripts/aws/load-ssm-env.sh` reads everything under the prefix and renders
`/opt/ecommerce/.env.production` with mode `600`.

Create them with `--type SecureString` (the value is never echoed):

```bash
REGION=us-east-1
PREFIX=/ecommerce

put() { aws ssm put-parameter --region "$REGION" --type SecureString --overwrite --name "$1" --value "$2" >/dev/null && echo "set $1"; }

# Required
put "$PREFIX/admin_username"                 "admin"
put "$PREFIX/admin_password_hash"            "$(node -e "const c=require('crypto'),s=c.randomBytes(16).toString('base64url');console.log('scrypt$'+s+'$'+c.scryptSync(process.argv[1],Buffer.from(s,'base64url'),64).toString('base64url'))" 'CHOOSE_A_STRONG_PASSWORD')"
put "$PREFIX/admin_session_secret"           "$(node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))")"
put "$PREFIX/public_base_url"                "http://<INSTANCE_PUBLIC_DNS>"
put "$PREFIX/vodafone_cash_number"           "010XXXXXXXXX"

# Optional — leave unset if you do not want them
put "$PREFIX/email_notifications_enabled"    "false"
put "$PREFIX/order_notification_email"       ""
put "$PREFIX/smtp_host"                      ""
put "$PREFIX/smtp_user"                      ""
put "$PREFIX/smtp_pass"                      ""
put "$PREFIX/public_contact_phone"           ""      # contact section stays phone-free
```

Naming rule: `/ecommerce/public-base-url` becomes the shell variable
`PUBLIC_BASE_URL`. Verify the mapping **without printing any value**:

```bash
scripts/aws/load-ssm-env.sh --list          # prints names only
```

The instance IAM policy only allows `ssm:GetParametersByPath` on
`/ecommerce/*` — it cannot read any other parameter in the account.

---

## 7. Teardown

```bash
cd infrastructure/terraform/free-tier-ec2
terraform plan -destroy
terraform destroy
```

Then confirm nothing is left running:

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending \
  --query 'Reservations[].Instances[].InstanceId' --output text
aws ebs list-snapshots --owner-ids self   # delete demo snapshots if you created any
```

> [!WARNING]
> Destroying the instance destroys `/opt/ecommerce/data` and
> `/opt/ecommerce/uploads/receipts` with it. Those paths live on the root EBS
> volume. Export anything you want to keep first (§8 of
> `DEPLOYMENT_SUMMARY.md` describes the on-disk format).

The optional budget, if enabled, is account-level and is removed by the same
`terraform destroy`. The SNS topic may be left behind if other budgets still
reference it — check before deleting.

---

## 8. What was verified locally vs. what still needs AWS

| Claim | Status |
| --- | --- |
| `terraform fmt -check -recursive` across all three modules | **Verified locally** |
| `terraform init -backend=false` + `terraform validate` for root, bootstrap and free-tier-ec2 | **Verified locally** |
| `terraform plan` with real credentials | **Requires AWS** — no credentials in this environment |
| Instance boots, user-data installs Docker/Compose/SSM | **Requires AWS** |
| SSM Run Command deployment end to end | **Requires AWS** |
| Budget alert delivery | **Requires AWS** + inbox confirmation |
| Let's Encrypt issuance | **Requires DNS** pointing at the instance |
| GitHub OIDC role assumption | **Requires GitHub configuration** (`AWS_ROLE_ARN`, `AWS_REGION`, `AWS_INSTANCE_ID`) |
