output "alb_sg_id" { value = aws_security_group.alb.id }
output "ecs_sg_id" { value = aws_security_group.ecs.id }
output "rds_sg_id" { value = aws_security_group.rds.id }
output "redis_sg_id" { value = aws_security_group.redis.id }

output "ecs_execution_role_arn" { value = aws_iam_role.ecs_execution.arn }
output "ecs_task_role_arn" { value = aws_iam_role.ecs_task.arn }

output "db_secret_id" { value = aws_secretsmanager_secret.db_password.id }
output "db_secret_arn" { value = aws_secretsmanager_secret.db_password.arn }
