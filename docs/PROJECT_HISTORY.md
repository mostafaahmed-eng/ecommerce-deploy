# Project history and attribution

## Canonical repository

The maintained project lives at:

- `mostafaahmed-eng/ecommerce-deploy`

All active application, infrastructure, testing, and deployment work should be made in that repository.

## Original DEPI prototype

This implementation incorporates the project direction and learning roadmap from:

- `mostafaahmed-eng/Automated-E-Commerce-Deployment-Platform`

The original repository established the DEPI final-project concept, a simple Flask/Nginx prototype, initial Kubernetes learning manifests, a product-table SQL sketch, and the phased DevOps roadmap. Its useful ideas have been evolved here into tested Node.js services, Docker Compose, AWS ECS Fargate, DynamoDB, Terraform, GitHub Actions OIDC, and deployment verification.

The original prototype remains available as an archive and historical reference; it is not a second deployment source.

## Original team credits

The original DEPI repository lists:

- Omar Samir — Team Lead
- Momen Ahmed
- Ahmed Ashraf
- Ahmed Emad
- Ahmed Fahmy
- Mostafa Anwar

These credits are preserved from the source README. Repository commits retain their original authorship and history.

## Consolidation decisions

| Original idea | Maintained implementation |
| --- | --- |
| Static Nginx frontend | Responsive Node.js frontend behind Nginx/ALB |
| Single Flask API | Seven focused Node.js services and API gateway |
| Hard-coded Flask products | Local embedded catalog plus persistent AWS DynamoDB catalog |
| DockerHub build only | Tested ECR build and ECS deployment pipeline |
| Permanent registry credentials | GitHub Actions OIDC with short-lived AWS credentials |
| Minikube-only images | AWS ECS as the supported production-like target |
| Empty Terraform/Ansible folders | Working Terraform for state, IAM, networking, ECR, ECS, ALB, logs, scaling, and DynamoDB |
| Planned validation | Automated tests, dependency audit, health checks, and deployment smoke test |

Code from the original Flask/Nginx prototype was not copied because the maintained services already provide broader, tested behavior. Its product-storage concept and project roadmap were retained and modernized.
