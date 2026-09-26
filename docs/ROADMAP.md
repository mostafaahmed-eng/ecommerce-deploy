# Delivery roadmap

This roadmap converts the original DEPI learning plan into verifiable repository outcomes.

## Completed in the maintained codebase

- [x] Repository structure and Codex instructions
- [x] Seven containerized application services
- [x] Local Docker Compose orchestration and health checks
- [x] Nginx reverse proxy and same-origin API routing
- [x] Automated service tests and dependency audit
- [x] AWS VPC, public subnets, security groups, and ALB in Terraform
- [x] ECR repositories with scan-on-push and lifecycle policies
- [x] ECS Fargate deployment with CloudWatch Logs and autoscaling
- [x] DynamoDB catalog with encryption, backups, seed data, and least-privilege task access
- [x] GitHub Actions CI/CD using AWS OIDC and immutable commit tags
- [x] Deployment stability wait and public smoke test
- [x] Remote-state and GitHub OIDC bootstrap

## Required before the first public deployment

- [ ] Run the full Docker Compose stack on a Docker-enabled workstation
- [ ] Bootstrap the selected AWS account and confirm the target region
- [ ] Configure `AWS_ROLE_ARN` and `TF_STATE_BUCKET` in GitHub
- [ ] Protect the `main` branch and `production` environment
- [ ] Merge the deployment branch and verify the first ECS rollout
- [ ] Record the application URL and baseline monthly cost

## Recommended portfolio improvements

- [ ] Add a custom domain, ACM certificate, HTTPS listener, and HTTP-to-HTTPS redirect
- [ ] Add CloudWatch alarms and an SNS notification destination
- [ ] Add structured JSON logs and application metrics
- [ ] Create a Grafana or CloudWatch dashboard
- [ ] Add load testing and document scaling behavior
- [ ] Add authentication before exposing cart or order mutation APIs
- [ ] Add an architecture diagram and deployment screenshots
- [ ] Record and test an explicit rollback exercise

## Production boundary

This codebase is intentionally a DevOps portfolio demo. A real store additionally requires authentication and authorization, customer/order persistence, inventory concurrency controls, a real PCI-compliant payment provider, secrets management, privacy controls, disaster-recovery targets, and security testing.
