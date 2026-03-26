# Module 13: Workspaces and Environments

## 1. Concept: Managing Multiple Environments

Almost every company has at least three environments: **Dev**, **Staging**, and **Prod**. 
How do you deploy the exact same Terraform code differently across them without copy-pasting code?

### Pattern A: Terraform Workspaces
A Terraform Workspace is simply an isolated state file hiding behind the same `terraform` command.
If you run `terraform workspace new staging`, Terraform creates a new backend folder for state and exposes an interpolation variable called `terraform.workspace` (which now equals `"staging"`).

### Pattern B: Directory-per-Environment
Create folders like `environments/dev/main.tf` and `environments/prod/main.tf`. Each calls the exact same child modules but passes different `tfvars` files and sets a different backend explicitly.

### Pattern C: Terragrunt
Terragrunt is a third-party wrapper for Terraform. It drastically reduces the boilerplate required for Pattern B, keeping your code exceptionally DRY (Don't Repeat Yourself) while providing rock-solid isolation.

---

## 2. Code Example: The Workspace Pattern

Here is how you use the native `terraform.workspace` to drive environment sizes:

```hcl
locals {
  # Map the current workspace to a specific environment name
  # If we are in the "default" workspace, we consider it "dev"
  env = terraform.workspace == "default" ? "dev" : terraform.workspace

  # Dynamic sizing based on the environment
  instance_sizes = {
    dev     = "t3.micro"
    staging = "t3.small"
    prod    = "m5.large"
  }
  
  # How many Fargate tasks should we run?
  replica_counts = {
    dev     = 1
    staging = 2
    prod    = 10
  }
  
  # Should we prevent RDS from being destroyed?
  db_deletion_protection = {
    dev     = false
    staging = true
    prod    = true
  }

  name_prefix = "app-${local.env}"
}

# Example 1: Sizing compute
resource "aws_db_instance" "example" {
  identifier          = "${local.name_prefix}-db"
  instance_class      = local.instance_sizes[local.env]
  deletion_protection = local.db_deletion_protection[local.env]
}

# Example 2: Sizing capacity
resource "aws_ecs_service" "api" {
  name          = "${local.name_prefix}-api"
  desired_count = local.replica_counts[local.env]
}
```

### The Workflow

```bash
# 1. Start in Dev
terraform workspace select default
terraform apply

# 2. Move to Staging
terraform workspace new staging
terraform apply 
# Because local.env evaluates to "staging", the exact same code
# now creates a LARGER database and 2 Fargate tasks instead of 1.
```

---

## 3. The "Why": What breaks if I skip this?

* **Workspace collision:** AWS requires many resource names to be globally unique (like S3 buckets) or unique within an account/region (like Target Groups). If you don't use `local.env` or `terraform.workspace` inside the `name` argument of your resources, running `terraform apply` in the "staging" workspace will attempt to overwrite the "dev" resources because their names collide.
* **Why do people dislike Workspaces?** In the workspace pattern, the *state* is isolated, but the *code* isn't. If you edit `main.tf` to test a new caching feature in Dev, but a coworker urgently needs to run `terraform apply` in Prod to fix a typo, your half-finished caching code will accidentally get deployed to Prod. This is why many teams prefer Pattern B/C (Directory-per-Env).

---

## 4. Hands-on Exercise

1. Open a terminal in a safe Terraform directory (like `exercise-01` from Module 1).
2. Run `terraform workspace list`. You should see `* default`.
3. Try to create a new workspace: `terraform workspace new testing`.
4. Open the `terraform console` and type `terraform.workspace`. Notice its value!
5. Delete the workspace: `terraform workspace select default` then `terraform workspace delete testing`.
