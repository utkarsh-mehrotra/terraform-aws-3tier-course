# Application Load Balancer
resource "aws_lb" "external" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnets

  # tfsec:ignore:aws-elb-drop-invalid-headers
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = "200"
    }
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.prefix}-api-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener_rule" "api_routing" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ECS Fargate
resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecr_repository" "api" {
  name                 = "${var.prefix}-api-service"
  image_tag_mutability = "IMMUTABLE"
  # tfsec:ignore:aws-ecr-repository-customer-key
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.prefix}-api"
  retention_in_days = 30
  # tfsec:ignore:aws-cloudwatch-log-group-customer-key
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.prefix}-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name         = "api-container"
      image        = "nginx:latest" # Placeholder image for initial deployment
      essential    = true
      portMappings = [{ containerPort = 8080 }]

      secrets = [
        { name = "DB_PASS", valueFrom = var.db_secret_arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

locals {
  service_desired_count = terraform.workspace == "prod" ? 4 : 2
}

resource "aws_ecs_service" "api" {
  name            = "${var.prefix}-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = local.service_desired_count

  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }

  network_configuration {
    subnets          = var.private_app_subnets
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api-container"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Application AutoScaling
resource "aws_appautoscaling_target" "api_target" {
  max_capacity       = terraform.workspace == "prod" ? 20 : 5
  min_capacity       = local.service_desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.prefix}-api-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api_target.resource_id
  scalable_dimension = aws_appautoscaling_target.api_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 75.0
  }
}
