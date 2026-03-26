# Module 7: Modules

## 1. Concept: Reusable Building Blocks

As your infrastructure grows, maintaining 5,000 lines of code in `main.tf` becomes impossible. A Terraform **Module** is simply a folder containing `.tf` files. Every Terraform configuration is technically a module (the "root module").

Modules allow you to package and reuse resource configurations. There are two types:
1. **Local Modules:** Folders in your own repository (e.g., `./modules/networking`).
2. **Community Modules:** Pre-built, community-tested modules pulled from the Terraform Registry or GitHub (e.g., `terraform-aws-modules/vpc/aws`).

### When to write your own vs. use community modules?
- **Community Modules:** Great for complex, standard components like a VPC or EKS cluster where the community has already solved edge cases (like dynamic subnet routing).
- **Local Modules:** Great for your company's specific, highly-opinionated patterns (e.g., a standard `company_microservice` module that wraps ECS, an ALB Target Group, and standard IAM roles together).

---

## 2. Code Example: Building and Calling a Module

### Step 1: Create the Local Module
Imagine we have a directory `./modules/s3_static_website` with these three files:

**`./modules/s3_static_website/variables.tf`** (The Module's Inputs)
```hcl
variable "bucket_name" { type = string }
variable "tags" { type = map(string) }
```

**`./modules/s3_static_website/main.tf`** (The Module's Logic)
```hcl
resource "aws_s3_bucket" "website" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document { suffix = "index.html" }
}
```

**`./modules/s3_static_website/outputs.tf`** (The Module's Outputs)
```hcl
output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.website.website_endpoint
}
```

### Step 2: Call the Module from the Root
In our project's root `main.tf`, we consume the module:

```hcl
# Call our custom local module
module "frontend_website" {
  source      = "./modules/s3_static_website" # Path to the local folder
  
  # These map directly to the variables in the module's variables.tf
  bucket_name = "my-company-frontend-prod"
  tags        = { Environment = "Prod", ManagedBy = "Terraform" }
}

# Call a Community Module from the Terraform Registry
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0" # ALWAYS pin community module versions!

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false # We want 3 NAT GWs for High Availability!
  one_nat_gateway_per_az = true
}

# We can reference outputs from modules using module.NAME.OUTPUT_NAME
resource "aws_security_group" "demo" {
  name   = "demo-sg"
  # Pulling the VPC ID created by the community module!
  vpc_id = module.vpc.vpc_id 
}
```

---

## 3. The "Why": What breaks if I skip this?

* **No Version Pinning (`version = "~> 5.0"`):** If you use a community module without pinning the version, running `terraform init -upgrade` might accidentally download v6.0. If v6.0 renames an input variable from `enable_nat_gateway` to `create_nat_gateway`, your next `terraform apply` will attempt to destroy your existing NAT Gateways. Production goes down.
* **Creating a "VPC Module" locally from scratch:** As seen in Module 3, writing a VPC by hand requires ~10 resources and complex `cidrsubnet` math. The `terraform-aws-modules/vpc/aws` module handles this gracefully. Don't reinvent the wheel for standard AWS networking.

---

## 4. Hands-on Exercise

1. Browse to [registry.terraform.io](https://registry.terraform.io).
2. Search for the `vpc` module published by `terraform-aws-modules`.
3. Read the documentation. Find where the "Inputs" and "Outputs" are listed.
4. Verify the source code link (usually points to GitHub). **Always look at the underlying resource code** of a community module before using it in production so you know exactly what it builds under the hood!
