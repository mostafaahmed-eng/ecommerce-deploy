# Codex repository instructions

## Goal

Maintain this repository as a safe, reproducible DevOps portfolio demo deployed to AWS ECS Fargate. The payment service is simulated and must never be described as a real payment integration.

## Before editing

- Read `README.md` and inspect the current branch and worktree.
- Preserve user changes and use a feature branch for non-trivial work.
- Never commit AWS credentials, Terraform state, `.env` files, kubeconfigs, tokens, or generated plans.
- Confirm the AWS account with `aws sts get-caller-identity` before any apply or destroy.

## Required checks

Run the relevant subset while developing and all checks before handoff:

```bash
npm ci
npm test
docker compose config --quiet
kubectl kustomize infrastructure/k8s > /tmp/ecommerce-kubernetes.yaml
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
```

When Docker is available, build every service and smoke-test `http://localhost:8080/api/health`.

## Architecture constraints

- Node.js 20 and CommonJS are the current service baseline.
- Keep public ingress limited to the ALB and frontend container port 3000.
- Keep release images tagged with immutable Git commit SHAs; `latest` is only a convenience tag.
- Use GitHub OIDC for AWS authentication. Do not introduce long-lived AWS keys.
- Keep Terraform state remote, encrypted, versioned, and outside Git.
- Prefer backward-compatible API changes and add tests for changed behavior.

## Deployment safety

- Pull requests validate but do not deploy.
- Only `main` may assume the production OIDC role.
- Never run `terraform apply` or `terraform destroy` without reviewing the saved plan.
- Treat deletion, force-delete, IAM expansion, new public ingress, and cost-increasing changes as requiring explicit user confirmation.
