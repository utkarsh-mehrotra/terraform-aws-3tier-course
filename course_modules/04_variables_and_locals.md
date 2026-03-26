# Module 4: Variables, Locals, and Expressions

## 1. Concept: Data Types and Manipulation

Terraform isn't just a static configuration language; it has a rich type system and function library for dynamically generating infrastructure.

**Where data comes from:**
- **Variables (`variable {}`):** Values injected from the outside (by the user, CI/CD pipeline, or a `.tfvars` file). Use these for things that *change between environments* (like instance sizes or counts).
- **Locals (`locals {}`):** Values generated *inside* your Terraform code. Use these to reduce repetition (like creating a standard naming prefix) or to massage data using functions before passing it to resources.
- **Hard-coded values:** Use these ONLY if the value will never, ever change regardless of the environment (e.g., protocol `"tcp"`).

**The Type System:**
- Primitive: `string`, `number`, `bool`
- Collection: `list(...)`, `map(...)`, `set(...)`
- Structural: `object({ ... })`, `tuple([ ... ])`

---

## 2. Code Example: Advanced Variables and Locals

**`variables.tf`**
```hcl
# 1. Complex Object with Validation
variable "vpc_config" {
  description = "Configuration for the VPC. Includes CIDR and enable_dns."
  type = object({
    cidr       = string
    enable_dns = bool
  })
  
  # Validation blocks ensure bad data fails during 'plan', not 'apply'
  validation {
    condition     = can(cidrnetmask(var.vpc_config.cidr))
    error_message = "The vpc_config.cidr must be a valid IPv4 CIDR block."
  }
}

# 2. Sensitive Variables (Terraform redacts these from console output)
variable "db_password" {
  description = "Master password for Aurora RDS"
  type        = string
  sensitive   = true
  nullable    = false # This prevents users from explicitly passing 'null'
}

# 3. Maps and Lists
variable "az_mapping" {
  description = "Maps an AZ to a specific network tier suffix"
  type        = map(number)
  default = {
    "us-east-1a" = 1
    "us-east-1b" = 2
    "us-east-1c" = 3
  }
}
```

**`main.tf` (Locals and Expressions)**
```hcl
locals {
  # 1. Standard naming prefix
  prefix = "myapp-${var.environment}"

  # 2. Conditionals (like a ternary operator)
  # If environment is prod, create 3 NAT gateways. Otherwise, create just 1.
  nat_gw_count = var.environment == "prod" ? 3 : 1

  # 3. For Expressions (Iterating over a list/map to create a new list/map)
  # Convert ["us-east-1a", "us-east-1b"] to ["Subnet a", "Subnet b"]
  subnet_names = [for az in keys(var.az_mapping) : "Subnet ${substr(az, -1, 1)}"]

  # 4. Function: try() and coalesce()
  # try() falls back to a default if an expression fails.
  # coalesce() returns the first non-null, non-empty string.
  primary_region = coalesce(var.aws_region, "us-east-1")

  # 5. Function: merge()
  # Merging common tags with resource-specific tags
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
  
  # 6. Function: zipmap()
  # Combines a list of keys and a list of values into a map
  keys_list   = ["api", "worker"]
  values_list = [8080, 5000]
  # Result: { "api" = 8080, "worker" = 5000 }
  port_map    = zipmap(local.keys_list, local.values_list)
}

# Example usage of merged tags
resource "aws_vpc" "main" {
  cidr_block = var.vpc_config.cidr
  tags       = merge(local.common_tags, { Name = "${local.prefix}-vpc" })
}
```

---

## 3. The "Why": What breaks if I skip this?

* **No `validation` blocks:** If a user passes `"potato"` as an IP address, Terraform will accept it, talk to AWS, and AWS will throw a massive, confusing API error. Catch errors early in `plan`.
* **No `sensitive = true`:** If you pass passwords into Terraform without this flag, every time someone runs `terraform plan`, the database password will be printed clearly in the CI/CD pipeline logs for all engineers to see.
* **Overusing Variables instead of Locals:** If you make users pass in `var.name_prefix`, `var.db_name_prefix`, and `var.alb_name_prefix`, your modules become horrible to use. Use `locals` to calculate these automatically from a single `var.project_name`.

---

## 4. Hands-on Exercise

1. Open `terraform console`.
2. Test the `flatten()` function, which is incredibly useful for nested data structures. Try:
   ```hcl
   > flatten([["a", "b"], ["c", "d"]])
   ```
3. Test a `for` expression filtering data using an `if` statement:
   ```hcl
   > [for num in [1, 2, 3, 4, 5] : num * 2 if num > 2]
   ```
   *(Notice how it only multiplies 3, 4, and 5).*
