# Module 6: Data Sources and Dynamic References

## 1. Concept: Reading the Real World

While `resource` blocks *create* infrastructure, `data` blocks *read* information about infrastructure that already exists. This allows Terraform configurations to be dynamic, portable, and responsive to the AWS environment they are deployed in.

**When to use variables vs data sources:**
- Use **Variables** when *you* need to tell Terraform what to do (e.g., `environment = "prod"`).
- Use **Data Sources** when Terraform needs to ask AWS for a fact (e.g., "What is the ID of the current AWS account?", "What are the availability zones in this region?", "What is the latest AMI for ECS?").

---

## 2. Code Example: Dynamic Configuration

Here is how we use Data Sources to make our 3-tier architecture entirely portable across any AWS account or region without changing a single variable.

```hcl
# 1. Get the current AWS Region (e.g., "us-east-1")
data "aws_region" "current" {}

# 2. Get the current AWS Account details (Account ID, ARN)
data "aws_caller_identity" "current" {}

# 3. Get all available Availability Zones in the current region
# Filtering out AZs that might be constrained or local zones
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# 4. Look up secrets stored in AWS Secrets Manager created by the Security team
# We don't define the password in Terraform variables; we fetch it securely!
data "aws_secretsmanager_secret" "db_password" {
  name = "prod/rds/mysql/master_password"
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}

# 5. Look up the latest Amazon Linux 2 AMI Optimized for ECS
# AWS constantly updates AMIs. A data source ensures we always boot the newest secure version.
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# 6. Compose IAM Policies dynamically
data "aws_iam_policy_document" "s3_access" {
  statement {
    actions   = ["s3:GetObject"]
    # We use the region and account ID dynamically to build the ARN
    resources = ["arn:aws:s3:::my-app-bucket-${data.aws_account_id.current.account_id}-*"]
  }
}
```

### Applying the Data

Now we use these dynamic values in our resources:

```hcl
resource "aws_subnet" "public" {
  # Dynamically loop over whatever AZs are found in this region!
  # If deployed in us-east-1 (6 AZs) vs eu-west-3 (3 AZs), the code adapts automatically.
  for_each          = toset(slice(data.aws_availability_zones.available.names, 0, 3))
  
  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, index(data.aws_availability_zones.available.names, each.key))
}

resource "aws_db_instance" "example" {
  # Pass the database password directly from Secrets Manager to RDS
  # This way, Terraform never sees the password as an input variable!
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
  # ... other config ...
}
```

### The `depends_on` Edge Case
Normally, `data` blocks run during the `terraform plan` phase (before any infrastructure changes are made). 
However, if a `data` block depends on a `resource` that hasn't been created yet, Terraform defers reading that data block until the `terraform apply` phase. If you aren't careful, this can cause "cannot determine value until apply" errors when using that data in a `count` or `for_each` loop.

---

## 3. The "Why": What breaks if I skip this?

* **Hardcoded AMIs (`ami = "ami-0c55b159cbfafe1f0"`):** An AMI ID is specific to a single region. If you hardcode it, your template will fail immediately if deployed to another region. Furthermore, when AWS patches a vulnerability, you have to manually update your code. Using `data.aws_ssm_parameter` solves both problems.
* **Hardcoded AZs (`["us-east-1a", "us-east-1b"]`):** Some AWS accounts don't have access to `us-east-1e`. If you hardcode AZ names, the code might work for you but fail for a coworker. `data.aws_availability_zones` ensures you only request AZs you actually have access to.

---

## 4. Hands-on Exercise

1. Open `terraform console`.
2. Let's inspect data sources live. Run the following (they don't require `main.tf` if you have AWS credentials loaded):
   ```hcl
   > data.aws_caller_identity.current.account_id
   > data.aws_region.current.name
   ```
   *Note: If `data` is empty in console, create a dummy `main.tf`, add the data block, run `terraform init` and `terraform plan`, then return to the console!*
