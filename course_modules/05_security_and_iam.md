# Module 5: Security Groups and IAM

## 1. Concept: The Shield and the Key

In AWS, security is primarily handled at two layers for our compute services:
1. **Network Layer (Security Groups):** Stateful firewalls surrounding EC2 instances, RDS databases, and ECS tasks. They control *who can talk to whom* over the network.
2. **Access Layer (IAM):** Identity and Access Management. Controls *what AWS API actions* a service can perform (e.g., "Can my ECS task read this S3 bucket?").

### The Golden Rules
- **Security Groups:** Never use hardcoded IP ranges for internal traffic. Instead, chain Security Groups together (e.g., "Allow port 3306 on RDS *only* if the traffic comes from the ECS Security Group").
- **IAM (Least Privilege):** Never grant `s3:*` or `AdministratorAccess`. Grant exactly the permissions needed to the exact resources needed.
- **Rule Separation:** Prefer using `aws_security_group` for the shell, and `aws_security_group_rule` for the rules. It prevents cyclic dependencies when SG "A" needs to talk to SG "B", and "B" needs to talk to "A".

---

## 2. Code Example: Network Firewalls and IAM Roles

### Part A: Security Group Chaining
```hcl
# 1. ALB Security Group (Public facing)
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow HTTPS inbound from anywhere"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "alb_https_in" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# 2. ECS Task Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 8080 # App port
  to_port                  = 8080
  protocol                 = "tcp"
  # CHAINING: We don't use IPs. We allow traffic FROM the ALB Security Group ID.
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_tasks.id
}

# 3. RDS Aurora Security Group
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 3306 # MySQL port
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.rds.id
}

# 4. Outbound rules (Egress) - Allow ECS to talk to the internet to pull images
resource "aws_security_group_rule" "ecs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # All protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
}
```

### Part B: IAM - Task Execution vs Task Role
- **Task Execution Role:** Used by the ECS *agent* to pull Docker images from ECR and send logs to CloudWatch.
- **Task Role:** Used by *your application code* inside the container to talk to S3, SQS, DynamoDB, etc.

```hcl
# Data blocks define Trust Policies (Who is allowed to assume this role?)
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Create the Task Role
resource "aws_iam_role" "app_task_role" {
  name               = "app-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

# Define what the application is allowed to do (Least Privilege)
# We use jsonencode() as an alternative to aws_iam_policy_document for cleaner syntax sometimes.
resource "aws_iam_policy" "app_permissions" {
  name = "app-permissions-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        # Only allow access to THIS specific bucket, not all S3 buckets!
        Resource = ["arn:aws:s3:::my-app-assets-bucket/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
        Resource = ["arn:aws:sqs:us-east-1:123456789012:worker-queue"]
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "app_role_attachment" {
  role       = aws_iam_role.app_task_role.name
  policy_arn = aws_iam_policy.app_permissions.arn
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Hardcoding IPs instead of SG IDs:** If you put `cidr_blocks = ["10.0.1.0/24"]` for your RDS database to allow ECS tasks, what happens if an ECS task scales into a different subnet? It loses database access. Chaining by `source_security_group_id` ensures that *any* ECS task, regardless of its IP, can talk to the DB.
* **Inline inline ingress blocks:** If you define `ingress {}` directly inside the `aws_security_group` resource, you cannot have circular dependencies. Splitting them into `aws_security_group_rule` allows SG "A" and SG "B" to point to each other without Terraform throwing a cycle error.
* **Using one IAM Role for everything:** If your App container and your Worker container share the same IAM role, a vulnerability in the App container allows hackers to read/write the Worker container's SQS queues. Always split roles.

---

## 4. Hands-on Exercise

Write an `aws_iam_policy_document` data block equivalent to the `jsonencode()` block shown above for S3 and SQS.
Compare the two syntaxes. `jsonencode()` looks exactly like raw AWS JSON. `aws_iam_policy_document` allows you to construct JSON using native HCL, which is deeply integrated with Terraform variables!
