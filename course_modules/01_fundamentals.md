# Module 1: Terraform Fundamentals

## 1. Concept: The Infrastructure as Code Engine

Terraform by HashiCorp is a declarative Infrastructure as Code (IaC) tool. You write code that defines *what* you want (the desired state), and Terraform figures out *how* to achieve it by talking to cloud provider APIs.

### The Core Lifecycle
1. **Write:** You author configuration files (`.tf`) declaring resources (e.g., a VPC or an EC2 instance).
2. **Init (`terraform init`):** Terraform downloads the necessary provider plugins (like the AWS provider) required to execute your code.
3. **Plan (`terraform plan`):** Terraform compares your desired state (the code) against the current real-world state, generating an execution plan of what it will create, update, or destroy.
4. **Apply (`terraform apply`):** Terraform executes the plan, making the API calls to build the resources.
5. **Destroy (`terraform destroy`):** Terraform tears down everything it created.

### State: The Source of Truth
To know what changed between runs, Terraform stores the mapping of your code to real-world resources in a JSON file called the **state file** (`terraform.tfstate`). This state is critical—it tells Terraform "Resource X in your code is ID `vpc-123456` in AWS."

---

## 2. Code Example: The 3-Tier Web App Foundation

Whenever starting a new project, we structure it using HashiCorp standard conventions: separating the configuration, variables, outputs, and versions. Let's create the root of our 3-tier web app.

**`versions.tf`** - Tells Terraform which core version and provider versions to use.
```hcl
terraform {
  # We require at least Terraform 1.5, which introduced import blocks and checks.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Pin the major version to prevent breaking changes (~> allows patch/minor updates)
      version = "~> 5.0"
    }
  }
}
```

**`main.tf`** - The primary entry point. We define the provider and any local variables.
```hcl
# The provider block tells Terraform how to authenticate to AWS
provider "aws" {
  region = var.aws_region

  # Default tags apply these tags to EVERY resource created in this AWS account.
  default_tags {
    tags = {
      Project     = "3-Tier-WebApp"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  }
}

# Locals are like constants or derived values. We'll use them extensively later.
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}
```

**`variables.tf`** - Input parameters for your code.
```hcl
variable "aws_region" {
  description = "The AWS region to deploy the infrastructure into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project, used for resource naming."
  type        = string
  default     = "tutorial-app"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
}
```

**`outputs.tf`** - Returns values back to the user or to other modules after execution.
```hcl
output "aws_region" {
  description = "The region the infrastructure was deployed in."
  value       = var.aws_region
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Skipping `required_version` or `required_providers`:** If you leave versions unpinned, one team member might use Terraform 1.5 while another uses 1.8, causing state file format incompatibilities. Or the AWS provider might upgrade to v6.0 and introduce breaking API changes that destroy your cluster.
* **Skipping `default_tags`:** Tracing cloud costs in AWS is a nightmare without tags. By skipping the `default_tags` block in the provider, your EC2 and RDS instances will be untagged, leaving your finance team blind to who owns what.
* **Putting everything in `main.tf`:** Terraform doesn't care if everything is in one file; it reads all `.tf` files in a directory. However, a 3,000-line `main.tf` will break your brain. Standardizing on `variables.tf`, `outputs.tf`, and `main.tf` keeps the team sane.

---

## 4. Hands-on Exercise

1. Create a folder named `exercise-01`.
2. Create the four files exactly as written above.
3. Open a terminal in that folder and run:
   ```bash
   terraform fmt
   ```
   *(Notice how Terraform automatically formats your spacing).*
4. Run:
   ```bash
   terraform init
   ```
   *(Look in the newly created `.terraform` folder to see the downloaded AWS provider).*
5. Run:
   ```bash
   terraform validate
   ```
   *(This ensures your syntax is correct).*
6. Run:
   ```bash
   terraform plan -var="environment=staging"
   ```
   *(You won't see any resources being created yet, but Terraform will successfully "talk" to AWS if your credentials are valid. Notice how we overrode the default variable).*
