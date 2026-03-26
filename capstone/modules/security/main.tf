# Security Groups
resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "ALB public access"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # tfsec:ignore:aws-vpc-no-public-ingress-sgr
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # tfsec:ignore:aws-vpc-no-public-ingress-sgr
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group" "ecs" {
  name        = "${var.prefix}-ecs-sg"
  description = "ECS tasks access"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "ecs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "RDS Aurora access"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group" "redis" {
  name        = "${var.prefix}-redis-sg"
  description = "ElastiCache Redis access"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "redis_from_ecs" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.redis.id
}

# IAM Roles
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.prefix}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_core" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_policy" "ecs_task_policy" {
  name = "${var.prefix}-ecs-task-custom-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_custom" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.prefix}/rds/master_password"
  # tfsec:ignore:aws-ssm-secret-use-customer-key
}
