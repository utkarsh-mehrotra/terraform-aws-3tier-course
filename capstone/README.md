# Capstone Project: 3-Tier AWS Architecture

This is the capstone project for the Terraform AWS 3-Tier Course. It is a fully functional, production-ready, highly-available infrastructure architecture configured using Terraform >= 1.5.0 and AWS ~> 5.0.

## Architecture

- **Networking:** VPC, 9 Subnets across 3 AZs, 3 NAT Gateways for HA, IGW, Route Tables.
- **Compute:** ECS Fargate Auto-Scaled Cluster, Application Load Balancer, ECR.
- **Data:** Aurora MySQL (1 Writer, 2 Readers), ElastiCache Redis (Cluster Mode).
- **Security:** Security Group Chaining, IAM Least-privilege Roles, AWS WAFv2, Secrets Manager.
- **Observability:** CloudWatch Dashboard, Metric Alarms, SNS Alerting, Log Groups.

## Structure

```text
.
├── modules/
│   ├── networking/   # Network core powered by community VPC module
│   ├── compute/      # ALB, ECS Fargate, ECR, ASG
│   ├── data/         # RDS Aurora, ElastiCache Redis
│   ├── security/     # Security Groups, IAM Roles, Secrets
│   └── observability/# Dashboards, Alarms, SNS
├── main.tf           # Composes all modules together
├── variables.tf      # Global inputs
├── outputs.tf        # Global outputs
├── versions.tf       # Provider pinning
├── terragrunt.hcl    # DRY Backend and Environment management
└── .tfsec/           # Security scanning baselines
```

## Usage

1. **Prerequisites:** Ensure you have Terraform `1.5+`, Terragrunt, and AWS credentials configured.
2. **Initialization:** Run `terragrunt init`.
3. **Planning (Dev):** Run `terragrunt plan`.
4. **Applying:** Run `terragrunt apply`.

*Note: The Aurora database password must be supplied via the `TF_VAR_db_password` environment variable before running plan/apply.*
