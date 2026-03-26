data "aws_kms_alias" "rds" { name = "alias/aws/rds" }

resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "${var.prefix}-aurora"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.04.1"
  database_name          = "appdb"
  master_username        = "admin"
  master_password        = var.db_password
  vpc_security_group_ids = [var.rds_security_group_id]
  db_subnet_group_name   = var.db_subnet_group_name
  storage_encrypted      = true
  kms_key_id             = data.aws_kms_alias.rds.target_key_arn

  backup_retention_period = 14
  preferred_backup_window = "02:00-04:00"

  deletion_protection = terraform.workspace != "default"
  skip_final_snapshot = terraform.workspace == "default"
}

resource "aws_rds_cluster_instance" "aurora_nodes" {
  count              = terraform.workspace == "default" ? 1 : 2
  identifier         = "${var.prefix}-aurora-node-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}

data "aws_subnets" "dbem" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.prefix}-redis"
  description          = "App Redis Cluster"
  node_type            = "cache.t3.micro"
  port                 = 6379
  subnet_group_name    = var.db_subnet_group_name
  security_group_ids   = [var.redis_security_group_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  automatic_failover_enabled = true
  multi_az_enabled           = true

  replicas_per_node_group = 1
  num_node_groups         = 2
}
