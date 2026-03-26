# Terraform AWS 3-Tier Course 🚀

Welcome to the **Terraform AWS 3-Tier Architecture Course**! This repository contains a progressive, 15-module curriculum designed for engineers looking to master HashiCorp Terraform and deploy production-grade infrastructure on AWS. 

It culminates in a real-world, highly-available **Capstone Project** ready for deployment.

---

## 📚 Course Curriculum (`/course_modules`)

The course is broken down into 15 focused modules. Each module provides conceptual explanations, working code snippets, the "why" behind best practices, and hands-on exercises.

### Foundations & Networking
* [Module 1: Terraform Fundamentals](course_modules/01_fundamentals.md)
* [Module 2: Remote State and Locking](course_modules/02_remote_state.md)
* [Module 3: VPC and Networking](course_modules/03_vpc_and_networking.md)

### Logic & Security
* [Module 4: Variables, Locals, and Expressions](course_modules/04_variables_and_locals.md)
* [Module 5: Security Groups and IAM](course_modules/05_security_and_iam.md)
* [Module 6: Data Sources and Dynamic References](course_modules/06_data_sources.md)

### Advanced Infrastructure (The 3 Tiers)
* [Module 7: Terraform Modules](course_modules/07_modules.md)
* [Module 8: ALB, ECS Fargate, and ECR (Compute Tier)](course_modules/08_compute_tier.md)
* [Module 9: RDS Aurora and ElastiCache (Data Tier)](course_modules/09_data_tier.md)

### Auxilliary Services & Observability
* [Module 10: S3, SQS, and Secrets Manager](course_modules/10_s3_sqs_secrets.md)
* [Module 11: Route 53, ACM, and WAF](course_modules/11_dns_acm_waf.md)
* [Module 12: CloudWatch, X-Ray, and Alarms](course_modules/12_observability.md)

### Operations & Day 2
* [Module 13: Workspaces and Environments](course_modules/13_workspaces.md)
* [Module 14: Terraform in CI/CD](course_modules/14_cicd.md)
* [Module 15: Advanced Patterns](course_modules/15_advanced_patterns.md)

---

## 🏗 The Capstone Project (`/capstone`)

Located in the `/capstone` directory, you will find the final, unified Terraform codebase that brings all 15 modules together into a deployable environment.

### Target Architecture
1. **Networking:** 9 Subnets across 3 Availability Zones, 3 NAT Gateways.
2. **Compute:** Serverless ECS Fargate tasks behind an Application Load Balancer with Auto Scaling.
3. **Data:** Aurora MySQL (Writer + Readers) and ElastiCache Redis Cluster.
4. **Security:** Least-privilege IAM roles, chained Security Groups, Secrets Manager, and AWS WAFv2.
5. **Observability:** CloudWatch Dashboards, Log Groups, SNS Alarms, and X-Ray Daemon sidecars.

### Getting Started with the Capstone
1. Navigate to `/capstone`.
2. Ensure you have the Terraform CLI installed (`v1.5.0` or higher).
3. Read the `capstone/README.md` for specific deployment instructions.

---
*Generated as part of an interactive AI-assisted learning journey.*
