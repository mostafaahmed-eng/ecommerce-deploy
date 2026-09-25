# Free-tier EC2 deployment profile

Cost-optimized **live demo** profile: one ARM64 EC2 instance running the whole
application with Docker Compose behind an Nginx reverse proxy.

This profile lives **next to** the ECS profile in
`infrastructure/terraform/` — nothing in the existing ECS/Kubernetes setup was
moved or deleted.

## Architecture

```text
Internet
   |
   v
AWS EC2 t4g.small (ARM64, Amazon Linux 2023)
   |
   +-- Nginx  (ports 80 / 443 only)
          |
          +-- frontend          :3000
          +-- API gateway  :4600
                 |
                 +-- backend    :4000
                 +-- payment    :4200
                 +-- search     :5000
                 +-- cart       :4300
                 +-- product    :4500
```

## What this profile deliberately does NOT create

| Avoided | Why |
| --- | --- |
| NAT Gateway | ~$0.045/h + data processing; the public subnet routes straight to the IGW |
| Application Load Balancer | ~$0.0225/h + LCU; Nginx on the instance terminates HTTP |
| ECS / Fargate | Task + vCPU charges; Compose on one box is free |
| RDS | Always-on instance hours; state lives on the instance's EBS volume |
| Secrets Manager | Per-secret monthly fee; secrets come from **SSM Parameter Store** (free) |
| Route 53 hosted zone | Not required — HTTP works on the instance IP/DNS |
| WAF | Per-rule + request fees |
| Elastic IP | An unattached EIP costs money; the address is dynamic instead |

## Resources created

- 1 VPC (10.40.0.0/16), 1 public subnet, 1 Internet Gateway, 1 public route table
- 1 security group: ingress 80/443, egress all, **no port 22**
- 1 EC2 `t4g.small`, AMI resolved from
  `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64`
- Encrypted gp3 root volume (20 GB, 3000 IOPS, 125 MiB/s baseline)
- 1 IAM role + instance profile (`AmazonSSMManagedInstanceCore` + read-only
  `/ecommerce/*`)
- Optional AWS Budget (**disabled by default**)

## Security posture

- **IMDSv2 required** (`http_tokens = "required"`, hop limit 1)
- Root EBS volume **encrypted**
- **No SSH**: administration is Session Manager / Run Command only
- Instance role cannot use `PowerUserAccess`; parameter access is scoped to a
  single prefix
- Application containers publish **no host ports** — only Nginx binds externally

## Usage

```bash
cd infrastructure/terraform/free-tier-ec2
cp terraform.tfvars.example terraform.tfvars   # terraform.tfvars is git-ignored

terraform init
terraform plan
terraform apply                                  # only when you intend to
```

Read the outputs:

```bash
terraform output -raw application_http_url
terraform output -raw ssm_instructions
```

## Verify (no SSH needed)

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
ecommerce-health
```

## Teardown

```bash
terraform destroy
```

## Cost expectations

At the time this deployment profile was prepared, AWS provides a **T4g free
trial** covering up to **750 aggregate instance-hours per month of
`t4g.small`**, available to new and existing AWS customers, through
**December 31, 2026**. Regular On-Demand billing starts **January 1, 2027**.

Other resources, surplus CPU credits, network usage, storage, public IPv4 usage
outside applicable allowances, and usage after the trial may incur charges.
Eligibility and AWS terms can change — confirm the current offer before you
rely on it.

Post-trial, this instance bills On-Demand at roughly **$12/month** for compute
(about **$17.25/month** including a public IPv4 address and a 20 GB gp3 volume)
when running 24/7. Stopping the instance stops compute and public IPv4 billing.

See
[`docs/AWS_FREE_TIER_DEPLOYMENT.md`](../../../docs/AWS_FREE_TIER_DEPLOYMENT.md)
for the full cost model and the pre-apply checklist. **Do not assume $0 forever.**
