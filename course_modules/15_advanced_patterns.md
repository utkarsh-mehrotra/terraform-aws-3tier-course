# Module 15: Advanced Patterns

## 1. Concept: Solving the Hard Edges

Terraform isn't just provisioning networks; sometimes you need to run arbitrary scripts, dynamically generate complex files, or refactor your state file without destroying production.

Here are the advanced tools you need to know.

---

## 2. Code Example: Advanced Logic

### Part A: Dynamic Blocks
Sometimes you need to conditionally add sub-blocks (like multiple `ingress` rules or `action` blocks) based on a variable list, rather than using the clunky `aws_security_group_rule` separation.

```hcl
variable "waf_rules" {
  type = list(string)
  default = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
}

resource "aws_wafv2_web_acl" "main" {
  name  = "app-waf"
  scope = "REGIONAL"
  
  default_action { allow {} }
  visibility_config { /* ... */ }

  # Creates a dynamic number of 'rule' blocks based on the list!
  dynamic "rule" {
    for_each = var.waf_rules
    content {
      name     = rule.value
      priority = rule.key # The index of the array

      override_action { none {} }

      statement {
        managed_rule_group_statement {
          name        = rule.value
          vendor_name = "AWS"
        }
      }
      visibility_config { /* ... */ }
    }
  }
}
```

### Part B: Template Files vs File
Loading external files keeps your Terraforms clean.

```hcl
# file() reads a static file exactly as is.
resource "aws_iam_policy" "static" {
  name   = "static-policy"
  policy = file("${path.module}/policies/bucket_policy.json")
}

# templatefile() injects Terraform variables into the file!
# Great for rendering EC2 User-Data initial boot scripts.
resource "aws_instance" "web" {
  ami           = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = "t3.micro"
  
  # Inside init-script.sh, ${db_url} will be replaced with the actual RDS URL
  user_data = templatefile("${path.module}/init-script.sh", {
    db_url = aws_rds_cluster.aurora.endpoint
  })
}
```

### Part C: Refactoring and State Manipulation (The Modern Way)

**1. `moved` Blocks (Terraform 1.1+)**
If you change a resource name from `aws_instance.web` to `aws_instance.api`, Terraform's default behavior is to destroy `web` and create `api` (DOWNTIME!). 
To rename it safely:
```hcl
# This tells Terraform: "Don't destroy. Just rename it in the state file."
moved {
  from = aws_instance.web
  to   = aws_instance.api
}
```

**2. `import` Blocks (Terraform 1.5+)**
Previously, importing resources required imperative CLI running `terraform import`. Now it's declarative!
```hcl
import {
  to = aws_s3_bucket.legacy_bucket
  id = "my-manually-created-bucket-name"
}
```

**3. `replace_triggered_by` (Lifecycle)**
If you rotate the database password, Terraform updates Secrets Manager, but ECS Fargate keeps running the old cached password until it is restarted!
```hcl
resource "aws_ecs_service" "api" {
  name = "app-api"
  
  lifecycle {
    # If the secret changes, Force a rolling restart of the ECS service automatically!
    replace_triggered_by = [
      aws_secretsmanager_secret_version.db_password
    ]
  }
}
```

### Part D: The Escape Hatch (Provisioners)
If Terraform doesn't support an API or you absolutely *must* run a local bash script:

```hcl
# terraform_data replaces the older null_resource in Terraform 1.4+
resource "terraform_data" "trigger_migration" {
  # Re-run this block every time the Docker image tag changes
  triggers_replace = [aws_ecs_task_definition.api.revision]

  provisioner "local-exec" {
    # Run a local database migration script on the CI/CD machine
    command = "./scripts/migrate-db.sh ${aws_rds_cluster.aurora.endpoint}"
  }
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Using `local-exec` everywhere:** Provisioners are the absolute last resort. They are fire-and-forget. If `./migrate-db.sh` fails halfway, Terraform doesn't know how to "rollback" or fix it on the next run. State becomes permanently disconnected from reality. 
* **Ignoring `moved` Blocks:** Deleting an EC2 instance to rename it is bad. Deleting an RDS database to rename it is a resume-generating event. Use `moved` blocks when refactoring modules.

---

## 4. Hands-on Exercise

We have completed the 15 modules! 
To prove your mastery, navigate to the `capstone` directory where we have assembled the entire architecture into an end-to-end Terraform codebase using all these patterns. Run `terraform init` and `terraform validate` to see it all come together.
