output "alb_dns_name" { value = aws_lb.external.dns_name }
output "alb_arn_suffix" { value = aws_lb.external.arn_suffix }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
