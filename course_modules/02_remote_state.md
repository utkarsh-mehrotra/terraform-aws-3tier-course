# Module 2: Remote State and Locking

## 1. Concept: Protecting the Source of Truth

As mentioned in Module 1, Terraform stores state in a local file called `terraform.tfstate`. 
If you are the only developer, local state is fine. But when you join a team:
1. **Sharing:** How does your coworker get the latest state file? Emailing it is a disaster.
2. **Concurrency:** What happens if you and a coworker run `terraform apply` at the exact same time? You could corrupt the state or trigger duplicate AWS API calls.
3. **Secrets:** The state file stores sensitive data (like database passwords) in plain text!

**The Solution: Remote State with Locking.**
We store the state file in an AWS S3 bucket (which solves sharing and allows encryption for secrets) and use an AWS DynamoDB table for "state locking" (which prevents concurrent execution).

### The Bootstrap Problem
How do you use Terraform to create the S3 bucket and DynamoDB table *where Terraform will store its own state*?
1. Write code for S3 and DynamoDB locally.
2. Run `apply` to create them (state is stored locally).
3. Add the `backend "s3"` block to `versions.tf`.
4. Run `terraform init`. Terraform will ask if you want to migrate your local state to the new S3 bucket. Say yes.

---

## 2. Code Example: Bootstrapping the Backend

Let's bootstrap the backend for our 3-tier architecture.

**`backend-bootstrap/main.tf`**
```hcl
provider "aws" {
  region = "us-east-1"
}

# The S3 bucket to store the state file
resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-company-terraform-state-48912" # Must be globally unique!
  
  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so we can recover corrupted state files
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Turn on server-side encryption by default to protect secrets inside the state
resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The DynamoDB table used for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-up-and-running-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID" # Critical requirement for Terraform locking!

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

Once applied, we would update our project's `versions.tf` from Module 1 to use this backend:

**`versions.tf` (Updated Project Root)**
```hcl
terraform {
  required_version = ">= 1.5.0"

  # The backend block configuring Remote State
  backend "s3" {
    bucket         = "my-company-terraform-state-48912"
    key            = "global/s3/terraform.tfstate" # The path inside the S3 bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}
```

### Essential State Commands

- **State Drift:** State drift occurs when someone manually changes an AWS resource in the AWS Console instead of Terraform.
- **`terraform refresh`:** (Deprecated, now integrated directly into `terraform plan`). It asks AWS "what does reality look like right now" and updates the state file.
- **`terraform state list`:** Shows every resource Terraform is currently tracking.
- **`terraform state mv`:** Renames a resource in the state file without destroying and recreating the actual AWS resource. Useful during refactoring.
- **`terraform import`:** Tells Terraform to start managing a resource that was created manually outside of Terraform.

---

## 3. The "Why": What breaks if I skip this?

* **No Remote State:** If your laptop dies, your state file dies with it. Good luck managing your production environment.
* **No `dynamodb_table` (Locking):** In a CI/CD pipeline, two PRs merged closely together could trigger two simultaneous `terraform apply` runs. AWS will receive conflicting API calls, resulting in a fractured infrastructure and corrupted state.
* **No `prevent_destroy`:** If someone accidentally runs `terraform destroy` on the backend code, it deletes the bucket holding the state file for the rest of your infrastructure. This is an extinction-level event for a DevOps team.

---

## 4. Hands-on Exercise

To verify your understanding of State commands:

1. Create an AWS S3 bucket **using the AWS web console** manually (name it something like `my-manual-test-bucket-uuid`).
2. Write a Terraform resource block for an `aws_s3_bucket` in `main.tf` locally, give it the exact same name, but don't run `apply`.
3. Run the `import` command to bring it under Terraform management:
   ```bash
   terraform import aws_s3_bucket.my_test_bucket my-manual-test-bucket-uuid
   ```
4. Run `terraform plan`. Terraform should say `No changes. Your infrastructure matches the configuration.`, proving that it imported the state successfully!
