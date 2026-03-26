output "aurora_endpoint" { value = aws_rds_cluster.aurora.endpoint }
output "redis_endpoint" { value = aws_elasticache_replication_group.redis.configuration_endpoint_address }
