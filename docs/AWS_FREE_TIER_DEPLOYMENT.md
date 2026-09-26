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

- **CPU credits.** This profile sets **`cpu_credits = "standard"`** (the new
  default), so the instance earns and spends burst credits only and **cannot
  accrue surplus CPU-credit charges**. If you deliberately switch to
  `cpu_credits = "unlimited"`, sustained CPU above the baseline bills per
  vCPU-hour once burst credits are exhausted — that overage is billable and is
  **not** covered by the T4g trial.
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
   beyond their own allowances. **Surplus CPU credits** on `t4g` are a separate,
   billable item — avoided here because the profile defaults to
   `cpu_credits = "standard"`, and re-introduced the moment you opt into
   `cpu_credits = "unlimited"`.
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

### 4a. CI/CD deployment gate (`ENABLE_FREE_TIER_DEPLOY`)

Nothing in this document is deployed automatically. The `deploy via SSM` job in
`.github/workflows/deploy-free-tier.yml` carries a three-part condition:

```yaml
if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request' && vars.ENABLE_FREE_TIER_DEPLOY == 'true'
```

| `ENABLE_FREE_TIER_DEPLOY` | Validation and image builds | AWS SSM deployment |
| --- | --- | --- |
| unset (the current state), `false`, or any other value | run normally | **skipped — no AWS access at all** |
| `true` | run normally | permitted on `refs/heads/main` |

The gate is a repository **variable**, not a secret: Settings → Secrets and
variables → Actions → Variables. Because `vars.<name>` evaluates to an empty
string when it does not exist, a **missing** variable behaves exactly like
`false` — the gate fails closed. AWS is therefore untouched until you
deliberately set `ENABLE_FREE_TIER_DEPLOY=true`.

Two related guard rails:

- **The legacy ECS profile in `ci-cd.yml` is manual only.** Its
  `provision-registry`, `build` and `deploy` jobs require `workflow_dispatch`
  **from `refs/heads/main`** *and* the boolean input `deploy_legacy_ecs = true`.
  An ordinary merge or push to `main` never runs `terraform apply` in that
  workflow. The ECS/ECR code is retained unchanged for reference.
- **Pull requests never publish.** `build-pr` builds `linux/amd64` and
  `linux/arm64` with `push: false`, performs no GHCR login and holds no
  `packages: write` permission, so PR code cannot create packages or move
  `:latest`.

---

### 4b. Least-privilege deployment role (`AWS_FREE_TIER_ROLE_ARN`)

This workflow does **not** use the broad legacy role. It assumes its own role,
`<project>-github-actions-free-tier`, exposed as the Actions secret
**`AWS_FREE_TIER_ROLE_ARN`** (bootstrap output `free_tier_role_arn`).

The complete AWS API surface of `deploy-free-tier.yml` is three calls, and the
policy is derived from exactly that:

| Call in the workflow | Action | Resource scope |
| --- | --- | --- |
| `aws-actions/configure-aws-credentials` | `sts:AssumeRoleWithWebIdentity` | trust policy only: `repo:mostafaahmed-eng/ecommerce-deploy` + `ref:refs/heads/main` + aud `sts.amazonaws.com` |
| `aws ssm send-command --document-name AWS-RunShellScript --instance-id …` | `ssm:SendCommand` | **both** `arn:aws:ssm:<region>:<acct>:document/AWS-RunShellScript` **and** `arn:aws:ec2:<region>:<acct>:instance/<AWS_INSTANCE_ID>` |
| `aws ssm get-command-invocation …` (poll, up to 60 attempts) | `ssm:GetCommandInvocation` | `Resource = "*"` — required, see below |

**Not granted:** `PowerUserAccess`, `AdministratorAccess`, `iam:*`, `ec2:*`,
`s3:*`, `ssm:*`. The GHCR image push uses `GITHUB_TOKEN` and touches no AWS
API, so it needs no IAM permission at all.

**Why `Resource = "*"` on `ssm:GetCommandInvocation`:** **Confirmed** against
the AWS Systems Manager Service Authorization Reference — `GetCommandInvocation`
exposes no resource type, i.e. it does not support resource-level permissions,
so a policy that omits `Resource "*"` simply denies it and the deployment poll
loop breaks. It therefore cannot be narrowed to the instance or the document.
`SendCommand`, by contrast, *does* support resource-level permissions and stays
scoped to `AWS-RunShellScript` plus the single EC2 instance.
Residual risk: a caller holding some other valid `CommandId` could read that
command's output — but this role cannot create a command against anything other
than the single instance above.

**Fail-closed default:** `var.free_tier_instance_id` is `null` until you set it
to the demo instance. While it is null the `ssm:SendCommand` statement only
matches a placeholder that is not a real instance ID, so the role cannot target
anything.

**Separation from the legacy profile:** `ci-cd.yml` uses the distinct secret
`AWS_LEGACY_ROLE_ARN`, which carries `PowerUserAccess` for its manual
`terraform apply` path. Neither workflow references the other's secret, and the
free-tier role has no path to `PowerUserAccess`.

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

### 7a. Free-plan expiry safety (temporary environment)

> [!CAUTION]
> **This environment is temporary.** The AWS account is on a time-limited Free
> plan (approximately **12 days remaining** at the time of writing). Nothing in
> this demo is meant to outlive it.

- **Destroy the demo before the Free plan expires** unless you explicitly
  choose to upgrade and start paying for it.
- **Recommended teardown target: at least 48 hours before Free-plan expiry.**
  Two days of slack covers retries, a failed destroy, or a state-file problem
  without pushing you past the deadline.
- Compute, public IPv4 and EBS all bill once the free allowance is gone —
  leaving a forgotten `t4g.small` running past expiry is exactly how a
  portfolio demo turns into an unexpected card charge.
- Set yourself a personal reminder now; **no AWS scheduled action, EventBridge
  rule or budget-triggered shutdown was created for this**, deliberately — an
  automated stop/destroy in your account would be an unreviewed, billable
  account-level control.
- To tear down:

  ```bash
  cd infrastructure/terraform/free-tier-ec2
  terraform plan -destroy
  terraform destroy
  ```

  **Do not run `terraform destroy` now** — it is documented here for the
  teardown day only.

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
| GitHub OIDC role assumption | **Requires GitHub configuration** (`AWS_FREE_TIER_ROLE_ARN`, `AWS_REGION`, `AWS_INSTANCE_ID`) |

---

## 9. End-to-end deployment order (AWS phase)

Follow these steps **in order**. `ENABLE_FREE_TIER_DEPLOY` stays disabled until
step 15.

1. Merge the security PR.
2. Authenticate locally to AWS (`aws configure` / `aws sso login`, then confirm
   with `aws sts get-caller-identity`).
3. `terraform plan` the free-tier EC2 profile
   (`infrastructure/terraform/free-tier-ec2`).
4. Review cost and the complete resource list. Confirm the plan shows
   **`cpu_credits: "standard"`** (cost-safe default) and that no NAT gateway,
   load balancer, Elastic IP or port-22 rule appears.
5. `terraform apply` the free-tier EC2 profile.
6. Obtain `instance_id` from that module's output.
7. Verify the instance appears as an SSM managed node
   (`aws ssm describe-instance-information` shows the ID as `PingStatus=Online`).
8. Run the bootstrap plan with all three set:

   | Variable | Value |
   | --- | --- |
   | `free_tier_instance_id` | `"<instance-id>"` |
   | `enable_legacy_ecs_role` | `false` |
   | `create_state_bucket` | `false` |

9. Review the bootstrap plan. With those defaults it must contain **only** the
   account OIDC provider (if none exists yet), the free-tier IAM role and its
   policy — **no `PowerUserAccess`, no legacy role, no S3 bucket.**
10. Apply the bootstrap.
11. Put the production application values into the `/ecommerce/*` SSM Parameter
    Store keys (§6).
12. Configure GitHub:
    - **secret** `AWS_FREE_TIER_ROLE_ARN` ← bootstrap output `free_tier_role_arn`
    - **variable** `AWS_REGION`
    - **variable** `AWS_INSTANCE_ID`
    - **variable** `APP_URL`
13. Keep `ENABLE_FREE_TIER_DEPLOY` **disabled** (leave it unset).
14. Perform a manual OIDC/SSM connectivity test — prove the trust policy and the
    least-privilege policy actually work before enabling anything.
15. Only then set `ENABLE_FREE_TIER_DEPLOY=true`.
16. **Diary the teardown date.** This environment is temporary — see §7a.
    Destroy the demo **at least 48 hours before the AWS Free plan expires**
    (`terraform destroy`, documented in §7a) unless you explicitly choose to
    upgrade and pay. Do this yourself; no automatic AWS shutdown was created.

### Legacy ECS setup — optional and unrelated to the live demo

The legacy ECS profile shares nothing with the demo above and is **never**
required to run the free-tier deployment. It is opt-in end to end:

- `enable_legacy_ecs_role = true` in the bootstrap creates the broad
  `AWS_LEGACY_ROLE_ARN` role. This is the **only** place `PowerUserAccess`
  exists in this repository, and it does not exist unless you ask for it.
- `create_state_bucket = true` only if you want the optional remote-state
  bucket the legacy ECS backend can use. The demo keeps Terraform state local.
- Separate GitHub settings: secret `AWS_LEGACY_ROLE_ARN`, secret
  `TF_STATE_BUCKET`, variables `AWS_REGION` / `PUBLIC_DOMAIN_NAME` /
  `ROUTE53_ZONE_ID`.
- It can only be triggered by `workflow_dispatch` from `refs/heads/main` with
  the boolean input `deploy_legacy_ecs = true`. A normal merge or push to
  `main` never runs it.
