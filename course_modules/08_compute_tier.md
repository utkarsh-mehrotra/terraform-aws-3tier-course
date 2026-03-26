# Module 8: ALB, ECS Fargate, and ECR

## 1. Concept: The Compute Tier

We are building a scalable containerized architecture. We need:
- **ECR (Elastic Container Registry):** To store our Docker images.
- **ALB (Application Load Balancer):** To receive HTTPS traffic from the internet and route it to our containers.
- **ECS (Elastic Container Service) on Fargate:** The orchestrator. Fargate means "serverless compute for containers"—we don't manage the underlying EC2 instances, AWS allocates CPU/Memory dynamically.
- **Auto Scaling:** To boot more containers if CPU usage spikes.

---

## 2. Code Example: Building Fargate APIs

### Part A: ECR and the ALB
```hcl
# 1. Container Registry
resource "aws_ecr_repository" "api" {
  name                 = "api-service"
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting old images, vital for rollbacks
}

# Automatically delete old untagged images to save money
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 30 images",
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 },
      action       = { type = "expire" }
    }]
  })
}

# 2. Application Load Balancer
resource "aws_lb" "external" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets # From our VPC module!
}

# HTTP redirects to HTTPS automatically
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
  }
}

# The routing destination for our API Task
resource "aws_lb_target_group" "api" {
  name        = "api-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip" # Required for Fargate!

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}
```

### Part B: ECS Fargate Cluster, Task Definition, and Service
```hcl
resource "aws_ecs_cluster" "main" {
  name = "app-cluster"
  # Enable ECS Exec so we can securely SSH into running containers for debug
  setting { name = "containerInsights", value = "enabled" } 
}

# The Blueprint for running a container
resource "aws_ecs_task_definition" "api" {
  family                   = "api-task"
  network_mode             = "awsvpc" # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # .25 vCPU
  memory                   = "512" # 512MB RAM
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.app_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "api-container"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8080 }]
      
      # Pull environment variables safely!
      environment = [{ name = "NODE_ENV", value = "production" }]
      secrets = [
        # Fetch actual DB password from Secrets Manager
        { name = "DB_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/api"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# The Service ensuring X tasks are always running
resource "aws_ecs_service" "api" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2 # Initial count

  # If a bad deployment occurs, automatically roll back instantly!
  deployment_circuit_breaker {
    enable   = true
    rollback = true 
  }

  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }

  network_configuration {
    # Place tasks in private subnets for security!
    subnets          = module.vpc.private_subnets 
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api-container"
    container_port   = 8080
  }
  
  # Ignore manual scaling changes so TF doesn't overwrite horizontal auto-scaling
  lifecycle { ignore_changes = [desired_count] }
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Missing `ignore_changes = [desired_count]`:** If AWS Auto Scaling scales your API from 2 tasks to 10 tasks overnight, and you run a `terraform apply` the next morning, Terraform will see your code says `desired_count = 2` and will ruthlessly kill 8 of your running production tasks to fix the drift. `ignore_changes` prevents this outage.
* **Missing `deployment_circuit_breaker`:** If you push a bad Docker image that crashes immediately, ECS will normally spend an hour restarting it constantly before giving up. The circuit breaker detects rapid crashing and rolls back to the previous healthy Terraform state automatically.
* **`assign_public_ip = true` on Fargate:** Placing Fargate tasks in the public subnet gives them public IPs, making them directly targetable by hackers bypassing your ALB, WAF, and Security Groups. Always put them in private subnets with `assign_public_ip = false`.

---

## 4. Hands-on Exercise

Locate the `container_definitions` JSON string in the Task Definition. Replace the `jsonencode` block with a **dynamic block** using the native HCL map format instead of JSON. 

Why use `jsonencode()` here at all? Because AWS natively expects a JSON string for this specific field. Using Terraform's `jsonencode` makes formatting drastically cleaner than escaping quotes inside a long string like `"[\"name\":\"foo\"]"`.
