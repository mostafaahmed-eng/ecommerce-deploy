# E-Commerce Deployment Platform

A portfolio-ready e-commerce microservices demo with reproducible local development and automated deployment to AWS ECS Fargate. This repository is the maintained implementation that consolidates the original DEPI project plan and prototype into one working codebase.

## What is included

- Seven Node.js services: frontend, API gateway, backend, product, cart, search, and demo payment.
- Docker Compose with health checks, isolated networking, non-root containers, and Nginx routing.
- Automated tests for service health and core product, cart, search, order, and payment behavior.
- Terraform for ECR, ECS Fargate, an Application Load Balancer, VPC networking, CloudWatch Logs, and autoscaling.
- A persistent DynamoDB product catalog on AWS, with an embedded catalog for zero-configuration local development.
- GitHub Actions CI/CD using short-lived AWS OIDC credentials—no permanent AWS access keys.
- ECR image scanning, immutable commit-SHA releases, build cache, SBOM/provenance, and deployment smoke tests.

> [!IMPORTANT]
> Vodafone Cash transfers are reviewed manually. A screenshot is not proof of payment: the owner must confirm the transfer in the actual Vodafone Cash account before marking an order as paid.

The project history, source-repository attribution, and team credits are recorded in [`docs/PROJECT_HISTORY.md`](docs/PROJECT_HISTORY.md). Current and future milestones are tracked in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Architecture

The AWS deployment uses one multi-container Fargate task to keep a demo environment reasonably small. Only the frontend port is reachable through the ALB. The remaining services communicate inside the task over localhost and are not publicly exposed. The product service reads the catalog from an encrypted DynamoDB table using a least-privilege ECS task role.

## Local development

Requirements: Node.js 20+, npm 10+, and Docker with Compose v2.

```bash
npm ci
npm test
docker compose up --build
```

Open `http://localhost:8080`. To use another local port:

```bash
HTTP_PORT=8088 docker compose up --build
```

Stop the environment with:

```bash
docker compose down --remove-orphans
```

## Manual Vodafone Cash payment

Copy `.env.example` to `.env` and configure the payment number plus the administrator settings. Never commit this file.

```bash
# Generate an scrypt password hash without printing it in CI logs.
node -e "const c=require('crypto'),s=c.randomBytes(16).toString('base64url');console.log('scrypt$'+s+'$'+c.scryptSync(process.argv[1],Buffer.from(s,'base64url'),64).toString('base64url'))" 'CHOOSE_A_STRONG_PASSWORD'
node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"
```

Set the first output as `ADMIN_PASSWORD_HASH` and the second as `ADMIN_SESSION_SECRET`. The local receipt volume is private to the payment container; it is not served by Nginx. Customers receive an order ID and a one-time tracking token, and must present both to check status or upload a receipt. The token is stored only as a SHA-256 hash.

The flow is: customer creates order → receives Vodafone Cash instructions → admin notification → customer transfers and uploads a receipt → owner checks the real transfer → owner approves or rejects → customer checks the final status. Receipt uploads only set `receipt_submitted`; they never set `paid`.

The owner dashboard API is under `/api/admin`; use `/admin` as the entry point. Authentication uses a password hash, HttpOnly SameSite=Strict session cookie, CSRF token, expiry, generic failures, and login rate limiting. For ECS, use AWS Secrets Manager to inject `ADMIN_USERNAME`, `ADMIN_PASSWORD_HASH`, `ADMIN_SESSION_SECRET`, and optional Telegram values. Do not set them as Terraform variables or task-definition plaintext.

For AWS receipts, configure a private encrypted S3 bucket with Block Public Access, lifecycle rules, and a payment-service-only IAM policy. The current local adapter is intended for Docker development; production should replace it with an S3 adapter that returns short-lived presigned URLs.

## First AWS deployment

Use an AWS account where you are allowed to create IAM, S3, VPC, ECR, ECS, CloudWatch, and load-balancer resources. The one-time bootstrap must be run by an authenticated AWS administrator from a trusted computer.

### 1. Authenticate locally

```bash
aws configure sso
aws sso login --profile YOUR_PROFILE
export AWS_PROFILE=YOUR_PROFILE
```

Confirm the target account before creating anything:

```bash
aws sts get-caller-identity
```

### 2. Bootstrap remote state and GitHub OIDC

```bash
cd infrastructure/terraform/bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output
```

The bootstrap creates:

- A private, encrypted, versioned S3 Terraform-state bucket.
- A GitHub OIDC trust limited to `mostafaahmed-eng/ecommerce-deploy` on the `main` branch.
- A deployment role with AWS `PowerUserAccess` plus IAM access limited to project-prefixed roles.

If the AWS account already contains the GitHub OIDC provider, import it instead of creating a duplicate:

```bash
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

### 3. Configure GitHub

In the repository settings, add these Actions secrets:

| Name | Value |
| --- | --- |
| `AWS_ROLE_ARN` | `github_actions_role_arn` from bootstrap output |
| `TF_STATE_BUCKET` | `state_bucket_name` from bootstrap output |

Optionally add the Actions variable `AWS_REGION`; it defaults to `us-east-1`.

Create a protected GitHub environment named `production` if deployment approval is required. Protect `main` and require the CI checks before merging.

### 4. Deploy

Push or merge to `main`. The workflow will:

1. Install dependencies, run tests, check Compose, and validate Terraform.
2. Provision ECR repositories on the first run.
3. Build and push all seven images tagged with the commit SHA.
4. plan and apply the AWS infrastructure.
5. Wait for ECS stability and smoke-test the public health endpoint.

The final ALB URL appears in the workflow summary and in the Terraform `application_url` output.

## Manual Terraform commands

For troubleshooting or a controlled manual deployment:

```bash
cd infrastructure/terraform
terraform init \
  -backend-config="bucket=YOUR_STATE_BUCKET" \
  -backend-config="key=ecommerce/production/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true"
terraform fmt -check -recursive
terraform validate
terraform plan -var="image_tag=COMMIT_SHA"
```

Do not apply an image tag that has not already been pushed to every ECR repository.

## Rollback

Each deployment uses an immutable Git commit SHA. The safest rollback is to rerun the workflow for a known-good commit or revert the bad commit and merge the revert. ECS retains previous task-definition revisions for emergency manual rollback.

## Cost and cleanup

AWS resources incur charges, notably Fargate and the Application Load Balancer. This design avoids a NAT Gateway and an EKS control-plane fee, but it is not free.

To remove the application infrastructure:

```bash
cd infrastructure/terraform
terraform destroy -var="allow_repository_force_delete=true"
```

Verify the exact account and plan before approving a destroy. Keep the bootstrap state bucket until the application state is no longer needed.

## Repository layout

```text
services/                      Node.js services and Dockerfiles
tests/                         Automated service tests
infrastructure/terraform/      AWS ECS infrastructure
infrastructure/terraform/bootstrap/  State bucket and GitHub OIDC
infrastructure/k8s/            Optional Kubernetes learning deployment
monitoring/                    Prometheus reference configuration
docs/                          Project history and delivery roadmap
.github/workflows/             CI/CD pipeline
```
